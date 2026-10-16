import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/device_identity.dart';
import '../core/crypto/pairing_payload.dart';
import '../core/crypto/secure_channel.dart';
import '../core/discovery/discovery_service.dart';
import '../core/discovery/broadcast_discovery_service.dart';
import '../core/discovery/composite_discovery_service.dart';
import '../core/discovery/nsd_discovery_service.dart';
import '../core/models/device.dart';
import '../core/models/intro.dart';
import '../core/models/transfer_item.dart';
import '../core/net/nearlink_client.dart';
import '../core/net/nearlink_server.dart';
import '../core/platform/background_keeper.dart';
import '../core/platform/notification_service.dart';
import '../core/storage/history_store.dart';
import '../core/storage/key_vault.dart';
import '../core/storage/settings_store.dart';
import '../core/storage/trust_store.dart';

/// The application's single source of truth: identity, discovery, trust,
/// transfers and settings, exposed to the widget tree via `provider`.
class AppState extends ChangeNotifier
    with WidgetsBindingObserver
    implements NearlinkServerDelegate {
  AppState({DiscoveryService? discovery})
      : _discovery = discovery ??
            CompositeDiscoveryService(<DiscoveryService>[
              // mDNS first, then the UDP beacon. Whichever works on a given
              // network wins; on Android the beacon is usually the one.
              NsdDiscoveryService(),
              BroadcastDiscoveryService(),
            ]);

  final DiscoveryService _discovery;
  final Uuid _uuid = const Uuid();

  late SharedPreferences _prefs;
  late SettingsStore _settings;
  late TrustStore _trust;
  late HistoryStore _history;
  late KeyVault _vault;

  late DeviceIdentity _identity;
  late NearlinkServer _server;
  late NearlinkClient _client;
  Directory _downloadDir = Directory.systemTemp;

  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  StreamSubscription<List<NearbyPeer>>? _peerSub;

  List<NearbyPeer> _peers = <NearbyPeer>[];
  Set<String> _localAddresses = <String>{};
  final Set<String> _probing = <String>{};
  List<TransferItem> _transfers = <TransferItem>[];
  String? _selectedDeviceId;
  PairingPayload? _pairingPayload;
  PairingPayload? _pendingPairRequest;
  TrustedDevice? _pendingUnpair;

  /// Introductions we are part of, keyed by intro id.
  final Map<String, IntroSession> _intros = <String, IntroSession>{};

  /// Introductions we arranged, so we can report how they turned out.
  final Map<String, String> _introducedPairs = <String, String>{};

  /// Anything that was slow or unavailable during startup. Emitted once
  /// the UI is up, since messages sent before then have no listener.
  final List<String> _startupWarnings = <String>[];
  bool _ready = false;
  bool _discoveryEnabled = true;
  Timer? _clipboardTimer;
  String? _lastLocalClipboard;
  String? _lastIncomingClipboard;

  /// Text received while we were backgrounded. Android refuses clipboard writes
  /// from a background app, so we hold it and apply it on resume.
  String? _pendingClipboard;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  // --- read-only views ---------------------------------------------------

  bool get isReady => _ready;
  DeviceIdentity get identity => _identity;
  List<NearbyPeer> get peers => List.unmodifiable(_peers);
  List<TrustedDevice> get trustedDevices => _trust.devices;
  List<TransferItem> get transfers => List.unmodifiable(_transfers);
  PairingPayload? get pairingPayload => _pairingPayload;

  /// Set when another device has asked to pair with us, so the UI can offer
  /// an Accept prompt.
  PairingPayload? get pendingPairRequest => _pendingPairRequest;

  /// Set when another device has removed us, so the UI can announce it
  /// and ask before dropping it here.
  TrustedDevice? get pendingUnpair => _pendingUnpair;

  /// An introduction waiting on this device to decide.
  IntroSession? get pendingIntro {
    for (final session in _intros.values) {
      if (session.awaitingUs) return session;
    }
    return null;
  }
  Stream<String> get messages => _messages.stream;
  bool get discoveryEnabled => _discoveryEnabled;

  /// Diagnostics: how many raw mDNS services we can see, and whether we are
  /// successfully advertising ourselves.
  int get discoveryServiceCount => _discovery.rawServiceCount;
  bool get discoveryAdvertising => _discovery.isAdvertising;
  bool get autoAcceptTrusted => _settings.autoAcceptTrusted;
  String get accountLabel => _settings.accountLabel;
  String get deviceName => _settings.deviceName ?? 'This device';

  /// Short descriptor shown beside the platform, e.g. "Nothing A001".
  String get deviceModel =>
      _settings.deviceModel ?? platformLabel(_currentPlatform());
  String get fingerprint => _identity.fingerprint;
  int get serverPort => _server.port;
  Directory get downloadDirectory => _downloadDir;

  TrustedDevice? get selectedDevice {
    final id = _selectedDeviceId;
    if (id == null) return null;
    return _trust.byId(id);
  }

  /// Trusted devices that are also currently visible on the network.
  List<TrustedDevice> get onlineDevices {
    final ids = _peers.map((p) => p.deviceId).toSet();
    return _trust.devices.where((d) => ids.contains(d.deviceId)).toList();
  }

  /// Discovered devices we have not paired with yet.
  List<NearbyPeer> get eligiblePeers {
    return _peers.where((p) => !_trust.contains(p.deviceId)).toList();
  }

  bool isOnline(String deviceId) =>
      _peers.any((p) => p.deviceId == deviceId);

  int get totalSharedBytes =>
      _transfers.fold<int>(0, (sum, t) => sum + t.bytes);

  int get sharedThisWeekBytes {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _transfers
        .where((t) => t.timestamp.isAfter(cutoff))
        .fold<int>(0, (sum, t) => sum + t.bytes);
  }

  // --- lifecycle ---------------------------------------------------------

  /// Await something plugin-backed, but never forever. A platform channel
  /// that never answers used to leave the app stuck on a blank screen,
  /// because main() waits for init() before drawing anything.
  Future<T?> _guarded<T>(
    String label,
    Future<T> Function() action, {
    Duration limit = const Duration(seconds: 6),
  }) async {
    try {
      return await action().timeout(limit);
    } catch (error) {
      _startupWarnings.add('$label: $error');
      return null;
    }
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _settings = SettingsStore(_prefs);
    _trust = TrustStore(_prefs)..load();
    _history = HistoryStore(_prefs);
    _vault = KeyVault(_prefs);

    await _loadOrCreateIdentity();

    if (_settings.deviceName == null) {
      final name = await _guarded('Reading the device name', _resolveDeviceName);
      await _settings.setDeviceName(name ?? 'Nearlink device');
    }
    if (_settings.deviceModel == null) {
      final model =
          await _guarded('Reading the device model', _resolveDeviceModel);
      await _settings.setDeviceModel(
        model ?? platformLabel(_currentPlatform()),
      );
    }

    _downloadDir =
        await _guarded('Choosing a folder for received files',
            _resolveDownloadDir) ??
            Directory.systemTemp;

    _server = NearlinkServer(
      identity: _identity,
      deviceName: deviceName,
      deviceModel: deviceModel,
      platform: _currentPlatform(),
      delegate: this,
      isTrusted: _trust.contains,
      downloadDirectory: _downloadDir,
    );
    // A missing network entitlement, or a socket that will not bind, should
    // degrade the app rather than kill it: the UI still opens and says so.
    await _guarded('Starting the receiving service', _server.start);

    _client = NearlinkClient(identity: _identity);

    _transfers = _history.load();
    _selectedDeviceId = _trust.devices.isEmpty ? null : _trust.devices.first.deviceId;

    await _guarded('Reading network addresses', _loadLocalAddresses);

    _discoveryEnabled = _settings.discoveryEnabled;
    _peerSub = _discovery.peers.listen(_onPeers);
    if (_discoveryEnabled) {
      // Deliberately not awaited: the mDNS plugin can stall on some
      // Android devices, and discovery is never worth a blank screen.
      unawaited(_startDiscovery());
    }

    _syncClipboardWatcher();
    unawaited(_syncBackgroundKeeper());
    unawaited(_initNotifications());
    WidgetsBinding.instance.addObserver(this);

    _ready = true;
    notifyListeners();

    for (final warning in _startupWarnings) {
      _emit(warning);
    }
  }

  Future<void> _loadOrCreateIdentity() async {
    final stored =
        await _guarded('Reading the device identity', _vault.readIdentity);
    if (stored != null && stored.isNotEmpty) {
      try {
        _identity = await DeviceIdentity.fromJson(
          jsonDecode(stored) as Map<String, dynamic>,
        );
        return;
      } catch (_) {
        // Corrupt; regenerate below.
      }
    }
    _identity = await DeviceIdentity.generate(_uuid.v4());
    await _guarded('Saving the device identity', () async {
      await _vault.writeIdentity(jsonEncode(await _identity.toJson()));
    });
  }

  Future<String> _resolveDeviceName() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return info.model;
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return info.name;
      }
      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return info.computerName;
      }
      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return info.computerName;
      }
      if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        return info.prettyName;
      }
    } catch (_) {}
    return 'Nearlink device';
  }

  /// Pick a directory we can actually write received files into.
  ///
  /// A sandboxed macOS build cannot write to the user's Downloads folder
  /// without the downloads read-write entitlement, and on Android
  /// [getDownloadsDirectory] is unsupported. So probe each candidate and take
  /// the first one that is genuinely writable, rather than assuming.
  Future<String> _resolveDeviceModel() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final maker = info.manufacturer.trim();
        final model = info.model.trim();
        if (model.isEmpty) return 'Android device';
        if (maker.isEmpty ||
            model.toLowerCase().startsWith(maker.toLowerCase())) {
          return model;
        }
        return '$maker $model';
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return info.utsname.machine;
      }
      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return info.productName;
      }
      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return info.model;
      }
      if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        return info.prettyName;
      }
    } catch (_) {}
    return platformLabel(_currentPlatform());
  }

  Future<Directory> _resolveDownloadDir() async {
    final candidates = <Directory>[];

    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) candidates.add(_nearlinkSubdir(downloads));
    } catch (_) {}

    if (Platform.isAndroid) {
      // External app storage is reachable over USB / file managers, unlike the
      // app's private internal directory.
      try {
        final external = await getExternalStorageDirectory();
        if (external != null) candidates.add(_nearlinkSubdir(external));
      } catch (_) {}
    }

    try {
      final support = await getApplicationSupportDirectory();
      candidates.add(_nearlinkSubdir(support));
    } catch (_) {}

    candidates.add(_nearlinkSubdir(Directory.systemTemp));

    for (final dir in candidates) {
      if (await _isWritable(dir)) return dir;
    }
    return Directory.systemTemp;
  }

  Directory _nearlinkSubdir(Directory base) =>
      Directory('${base.path}${Platform.pathSeparator}Nearlink');

  Future<bool> _isWritable(Directory dir) async {
    try {
      if (!dir.existsSync()) await dir.create(recursive: true);
      final probe =
          File('${dir.path}${Platform.pathSeparator}.nearlink-write-test');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  DevicePlatform _currentPlatform() {
    if (Platform.isAndroid) return DevicePlatform.android;
    if (Platform.isIOS) return DevicePlatform.ios;
    if (Platform.isWindows) return DevicePlatform.windows;
    if (Platform.isMacOS) return DevicePlatform.macos;
    if (Platform.isLinux) return DevicePlatform.linux;
    return DevicePlatform.unknown;
  }

  Future<String> localAddress() async {
    if (_localAddresses.isEmpty) await _loadLocalAddresses();
    if (_localAddresses.isNotEmpty) return _localAddresses.first;
    return '127.0.0.1';
  }

  // --- discovery ---------------------------------------------------------

  Future<void> _startDiscovery() async {
    try {
      await _discovery.start(
        deviceId: _identity.deviceId,
        deviceName: deviceName,
        platform: _currentPlatform(),
        port: _server.port,
        fingerprint: _identity.fingerprint,
        agreementKey: _identity.agreementPublicKeyBase64,
        model: deviceModel,
      );
    } catch (error) {
      _emit('Nearby discovery unavailable: $error');
    }
  }

  void _onPeers(List<NearbyPeer> peers) {
    _peers = peers.where((p) => !_isSelf(p)).toList();
    notifyListeners();
    unawaited(_enrichPeers());
  }

  /// Drop our own advertisement. With TXT records unreliable, the peer's id may
  /// fall back to the service name, so also match on our own address + port.
  bool _isSelf(NearbyPeer peer) {
    if (peer.deviceId == _identity.deviceId) return true;
    return _server.port != 0 &&
        peer.port == _server.port &&
        _localAddresses.contains(peer.host);
  }

  /// mDNS may only give us host + port. Ask the peer's `/info` endpoint for the
  /// real device id, name, platform and keys, so trust and the "nearby" state
  /// line up with what pairing stored.
  Future<void> _enrichPeers() async {
    for (final peer in List<NearbyPeer>.of(_peers)) {
      if (peer.fingerprint.isNotEmpty && peer.agreementKey.isNotEmpty) continue;
      final key = '${peer.host}:${peer.port}';
      if (!_probing.add(key)) continue; // already probing this peer
      try {
        final info = await _client.fetchInfo(peer.host, peer.port);
        if (info.deviceId == _identity.deviceId) continue;
        final index = _peers.indexWhere(
          (p) =>
              (p.host == peer.host && p.port == peer.port) ||
              p.deviceId == peer.deviceId,
        );
        if (index < 0) continue;
        _peers[index] = NearbyPeer(
          deviceId: info.deviceId,
          name: info.name,
          platform: info.platform,
          host: peer.host,
          port: peer.port,
          fingerprint: info.fingerprint,
          agreementKey: info.agreementKey,
          discoveredAt: peer.discoveredAt,
        );
        notifyListeners();
      } catch (_) {
        // Unreachable right now; keep the mDNS-only entry.
      } finally {
        _probing.remove(key);
      }
    }
    await _rememberAddresses();
    await _retryPendingRevocations();
  }

  Future<void> _loadLocalAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      _localAddresses = <String>{
        for (final interface in interfaces)
          for (final address in interface.addresses) address.address,
      };
    } catch (_) {
      _localAddresses = <String>{};
    }
  }

  Future<void> setDiscoveryEnabled(bool value) async {
    _discoveryEnabled = value;
    await _settings.setDiscoveryEnabled(value);
    if (value) {
      await _startDiscovery();
      _emit('Nearby discovery on');
    } else {
      await _discovery.stop();
      _peers = <NearbyPeer>[];
      _emit('Nearby discovery off');
    }
    notifyListeners();
  }

  // --- device selection & trust -----------------------------------------

  void selectDevice(String deviceId) {
    _selectedDeviceId = deviceId;
    notifyListeners();
  }

  Future<void> removeDevice(String deviceId) async {
    final device = _trust.byId(deviceId);
    await _trust.remove(deviceId);
    _client.forget(deviceId);
    if (_selectedDeviceId == deviceId) {
      _selectedDeviceId =
          _trust.devices.isEmpty ? null : _trust.devices.first.deviceId;
    }
    if (device != null) {
      _emit('${device.name} removed from trusted devices');
      unawaited(_notifyUnpair(device));
    }
    notifyListeners();
  }

  /// Tell the removed device, so it stops listing us. If it is offline, queue
  /// the revocation and try again when it next appears.
  Future<void> _notifyUnpair(TrustedDevice device) async {
    final address = _addressFor(device);
    if (address == null) {
      await _trust.addPendingRevocation(device.deviceId);
      return;
    }
    try {
      await _client.unpair(host: address.host, port: address.port);
    } catch (_) {
      await _trust.addPendingRevocation(device.deviceId);
    }
  }

  /// Another device told us it removed us. We announce it and ask before
  /// dropping it here, so a removal is never silent.
  @override
  Future<void> onUnpaired(String deviceId) async {
    final device = _trust.byId(deviceId);
    if (device == null) return;
    _pendingUnpair = device;
    notifyListeners();
  }

  /// Confirm a removal notice: only now is the device actually dropped.
  Future<void> acknowledgeUnpair() async {
    final device = _pendingUnpair;
    if (device == null) return;
    _pendingUnpair = null;
    await _trust.remove(device.deviceId);
    _client.forget(device.deviceId);
    if (_selectedDeviceId == device.deviceId) {
      _selectedDeviceId =
          _trust.devices.isEmpty ? null : _trust.devices.first.deviceId;
    }
    _emit('${device.name} removed this device');
    notifyListeners();
  }

  /// Remember where trusted devices were last seen, so we can reach them again
  /// even if discovery misses them next time.
  Future<void> _rememberAddresses() async {
    for (final peer in _peers) {
      final device = _trust.byId(peer.deviceId);
      if (device == null) continue;
      if (device.lastHost == peer.host && device.lastPort == peer.port) {
        continue;
      }
      await _trust.add(device.copyWith(
        lastHost: peer.host,
        lastPort: peer.port,
        lastSeen: DateTime.now(),
      ));
    }
  }

  Future<void> _retryPendingRevocations() async {
    final pending = _trust.pendingRevocations;
    if (pending.isEmpty) return;
    for (final id in pending) {
      for (final peer in _peers) {
        if (peer.deviceId != id) continue;
        try {
          await _client.unpair(host: peer.host, port: peer.port);
          await _trust.clearPendingRevocation(id);
        } catch (_) {
          // Still unreachable; keep it queued.
        }
        break;
      }
    }
  }

  // --- pairing -----------------------------------------------------------

  /// Create (or refresh) the payload another device scans or types in.
  Future<PairingPayload> beginPairing() async {
    final host = await localAddress();
    final token = base64Url.encode(SecureChannel.randomBytes(32));
    final pin = (SecureChannel.randomBytes(4).fold<int>(0, (a, b) => a * 256 + b) % 1000000)
        .toString()
        .padLeft(6, '0');
    final payload = PairingPayload(
      deviceId: _identity.deviceId,
      deviceName: deviceName,
      platform: _currentPlatform(),
      model: deviceModel,
      agreementKey: _identity.agreementPublicKeyBase64,
      identityKey: _identity.signingPublicKeyBase64,
      fingerprint: _identity.fingerprint,
      host: host,
      port: _server.port,
      token: token,
      pin: pin,
      createdAt: DateTime.now(),
    );
    _pairingPayload = payload;
    _server.offerPairing(payload);
    notifyListeners();
    return payload;
  }

  /// Pair by scanning another device's QR payload.
  Future<bool> pairWithPayload(PairingPayload payload) async {
    if (payload.deviceId == _identity.deviceId) {
      _emit('That is this device');
      return false;
    }
    try {
      final device = await _client.pairWith(
        host: payload.host,
        port: payload.port,
        secret: payload.token,
        name: deviceName,
        platform: _currentPlatform().name,
        model: deviceModel,
      );
      if (device.fingerprint != payload.fingerprint) {
        _emit('Pairing rejected: fingerprint mismatch');
        return false;
      }
      await _adoptPairedDevice(device);
      return true;
    } catch (error) {
      _emit('Pairing failed: $error');
      return false;
    }
  }

  /// Pair by typing the host, port and PIN shown on the other device.
  Future<bool> pairManually({
    required String host,
    required int port,
    required String pin,
  }) async {
    try {
      final device = await _client.pairWith(
        host: host,
        port: port,
        secret: pin.trim(),
        name: deviceName,
        platform: _currentPlatform().name,
        model: deviceModel,
      );
      await _adoptPairedDevice(device);
      return true;
    } catch (error) {
      _emit('Pairing failed: $error');
      return false;
    }
  }

  Future<void> _adoptPairedDevice(TrustedDevice device) async {
    await _trust.add(device);
    _selectedDeviceId ??= device.deviceId;
    _emit('${device.name} is now a trusted device');
    notifyListeners();
  }

  // --- outgoing transfers ------------------------------------------------

  Future<void> sendFiles(
    List<PlatformFile> files, {
    bool chainToAll = false,
  }) async {
    if (chainToAll) {
      await sendFilesChain(files);
      return;
    }
    final device = selectedDevice;
    if (device == null) {
      _emit('Choose a trusted device first');
      return;
    }
    if (files.isEmpty) return;

    NearlinkSession session;
    try {
      session = await _connect(device);
    } catch (error) {
      _emit(_reachError(device, error));
      return;
    }

    for (final file in files) {
      final path = file.path;
      if (path == null) continue;
      final size = file.size;
      final item = TransferItem(
        id: _uuid.v4(),
        kind: TransferKind.file,
        direction: TransferDirection.outgoing,
        peerId: device.deviceId,
        peerName: device.name,
        title: file.name,
        bytes: size,
        timestamp: DateTime.now(),
        status: TransferStatus.active,
        filePath: path,
      );
      _addTransfer(item);
      try {
        await _client.sendFile(
          session: session,
          filePath: path,
          fileName: file.name,
          size: size,
          mime: file.extension == null ? null : 'application/${file.extension}',
          onProgress: (sent) => _updateTransfer(
            item.id,
            (t) => t.copyWith(transferred: sent, status: TransferStatus.active),
          ),
        );
        _updateTransfer(
          item.id,
          (t) => t.copyWith(transferred: size, status: TransferStatus.delivered),
        );
      } catch (error) {
        _updateTransfer(
          item.id,
          (t) => t.copyWith(status: TransferStatus.failed, error: '$error'),
        );
        _emit('Failed to send ${file.name}');
      }
    }
    await _trust.touch(device.deviceId);
    _emit('${files.length} file${files.length == 1 ? '' : 's'} sent to ${device.name}');
  }

  /// Send files sequentially to all connected (online) trusted devices like a chain.
  ///
  /// If [targetDeviceIds] is provided, chains across those devices; otherwise
  /// chains across all [onlineDevices] (or all trusted devices if none are online yet).
  ///
  /// Each device in the chain receives the files in sequence, with individual progress
  /// tracking and notifications for each link in the chain.
  Future<int> sendFilesChain(
    List<PlatformFile> files, {
    Iterable<String>? targetDeviceIds,
  }) async {
    final targets = targetDeviceIds != null
        ? targetDeviceIds
            .map((id) => _trust.byId(id))
            .whereType<TrustedDevice>()
            .toList()
        : (onlineDevices.isNotEmpty ? onlineDevices : _trust.devices);

    if (targets.isEmpty) {
      _emit('No connected devices to chain to');
      return 0;
    }
    final validFiles = files.where((f) => f.path != null).toList();
    if (validFiles.isEmpty) return 0;

    var deliveredCount = 0;
    final totalTargets = targets.length;
    var index = 0;
    final chainLabel = 'Chain of $totalTargets';

    for (final device in targets) {
      index++;
      NearlinkSession session;
      try {
        session = await _connect(device);
      } catch (error) {
        _emit('Chain ($index/$totalTargets): ${_reachError(device, error)}');
        continue;
      }

      var anyFailed = false;
      for (final file in validFiles) {
        final path = file.path!;
        final size = file.size;
        final item = TransferItem(
          id: _uuid.v4(),
          kind: TransferKind.file,
          direction: TransferDirection.outgoing,
          peerId: device.deviceId,
          peerName: device.name,
          title: file.name,
          bytes: size,
          timestamp: DateTime.now(),
          status: TransferStatus.active,
          filePath: path,
          groupName: chainLabel,
        );
        _addTransfer(item);
        try {
          await _client.sendFile(
            session: session,
            filePath: path,
            fileName: file.name,
            size: size,
            mime: file.extension == null ? null : 'application/${file.extension}',
            onProgress: (sent) => _updateTransfer(
              item.id,
              (t) => t.copyWith(transferred: sent, status: TransferStatus.active),
            ),
          );
          _updateTransfer(
            item.id,
            (t) => t.copyWith(transferred: size, status: TransferStatus.delivered),
          );
        } catch (error) {
          anyFailed = true;
          _updateTransfer(
            item.id,
            (t) => t.copyWith(status: TransferStatus.failed, error: '$error'),
          );
          _emit('Chain: failed to send ${file.name} to ${device.name}');
        }
      }

      await _trust.touch(device.deviceId);
      if (!anyFailed) {
        deliveredCount++;
        _emit('Chain ($index/$totalTargets): sent to ${device.name}');
      }
    }

    _emit('Chain complete: delivered to $deliveredCount of $totalTargets connected device${totalTargets == 1 ? '' : 's'}');
    return deliveredCount;
  }

  /// Send to the currently selected device (the control-centre button).
  Future<void> sendClipboard(String text) async {
    final device = selectedDevice;
    if (device == null) {
      _emit('Choose a trusted device first');
      return;
    }
    await sendClipboardToDevices(<String>[device.deviceId], text);
  }

  /// Send the same text to several devices at once. Returns how many accepted
  /// it. [quiet] suppresses the per-device toasts (used by auto-sync).
  Future<int> sendClipboardToDevices(
    Iterable<String> deviceIds,
    String text, {
    bool quiet = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      if (!quiet) _emit('Paste something into the clipboard first');
      return 0;
    }
    final preview = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    final title = preview.length > 40 ? '${preview.substring(0, 40)}…' : preview;

    var sent = 0;
    for (final id in deviceIds.toSet()) {
      final device = _trust.byId(id);
      if (device == null) continue;
      try {
        final session = await _connect(device);
        await _client.sendClipboard(session: session, text: trimmed);
        _addTransfer(TransferItem(
          id: _uuid.v4(),
          kind: TransferKind.clipboard,
          direction: TransferDirection.outgoing,
          peerId: device.deviceId,
          peerName: device.name,
          title: title,
          bytes: trimmed.length,
          transferred: trimmed.length,
          timestamp: DateTime.now(),
          status: TransferStatus.delivered,
          payload: _capClipboard(trimmed),
        ));
        sent++;
        if (!quiet) _emit('Clipboard sent to ${device.name}');
      } catch (error) {
        if (!quiet) _emit(_reachError(device, error));
      }
    }
    if (quiet && sent > 0) {
      _emit('Clipboard synced to $sent device${sent == 1 ? '' : 's'}');
    }
    return sent;
  }

  /// Send to every trusted device.
  Future<int> sendClipboardToAllTrusted(String text, {bool quiet = false}) =>
      sendClipboardToDevices(
        _trust.devices.map((d) => d.deviceId),
        text,
        quiet: quiet,
      );

  /// Where to reach a device: live discovery first, then the last address we
  /// successfully saw it at. That fallback is what lets messaging and clipboard
  /// keep working when mDNS is being flaky.
  ({String host, int port})? _addressFor(TrustedDevice device) {
    for (final peer in _peers) {
      if (peer.deviceId == device.deviceId) {
        return (host: peer.host, port: peer.port);
      }
    }
    final host = device.lastHost;
    final port = device.lastPort;
    if (host != null && port != null && port != 0) {
      return (host: host, port: port);
    }
    return null;
  }

  /// Turn a connection failure into something the person can act on.
  String _reachError(TrustedDevice device, Object error) {
    if (error is StateError) {
      return '${device.name} is not visible on the network right now';
    }
    final detail = error.toString();
    if (detail.contains('403')) {
      return '${device.name} no longer trusts this device — pair again';
    }
    if (detail.contains('401')) {
      return '${device.name} rejected the session — try again';
    }
    if (detail.contains('404')) {
      return '${device.name} is running an older build — update it';
    }
    return '${device.name} was found but did not answer — is Nearlink open '
        'and in the foreground on it?';
  }

  Future<NearlinkSession> _connect(TrustedDevice device) async {
    final address = _addressFor(device);
    if (address == null) throw StateError('device not nearby');
    try {
      return await _client.handshake(
        host: address.host,
        port: address.port,
        expectedFingerprint: device.fingerprint,
        useCache: false,
      );
    } catch (_) {
      // One retry: the first attempt can lose a race with a peer that has just
      // restarted or moved ports since discovery saw it.
      _client.forget(device.deviceId);
      return _client.handshake(
        host: address.host,
        port: address.port,
        expectedFingerprint: device.fingerprint,
        useCache: false,
      );
    }
  }

  // --- incoming (NearlinkServerDelegate) ---------------------------------

  @override
  Future<void> onPaired(TrustedDevice device) async {
    await _adoptPairedDevice(device);
  }

  @override
  Future<void> onFileReceived({
    required String fromDeviceId,
    required String fromName,
    required String transferId,
    required String fileName,
    required int size,
    required String path,
  }) async {
    final device = _trust.byId(fromDeviceId);
    _addTransfer(TransferItem(
      id: transferId.isEmpty ? _uuid.v4() : transferId,
      kind: TransferKind.file,
      direction: TransferDirection.incoming,
      peerId: fromDeviceId,
      peerName: device?.name ?? fromName,
      title: fileName,
      bytes: size,
      transferred: size,
      timestamp: DateTime.now(),
      status: TransferStatus.delivered,
      filePath: path,
    ));
    await _trust.touch(fromDeviceId);
    _emit('${device?.name ?? 'A device'} sent you $fileName');
    await _notify(
      title: 'File received',
      body: '$fileName from ${device?.name ?? fromName}',
    );
  }

  @override
  Future<void> onClipboardReceived({
    required String fromDeviceId,
    required String fromName,
    required String text,
  }) async {
    final device = _trust.byId(fromDeviceId);
    final preview = text.replaceAll(RegExp(r'\s+'), ' ');
    _addTransfer(TransferItem(
      id: _uuid.v4(),
      kind: TransferKind.clipboard,
      direction: TransferDirection.incoming,
      peerId: fromDeviceId,
      peerName: device?.name ?? fromName,
      title: preview.length > 40 ? '${preview.substring(0, 40)}…' : preview,
      bytes: text.length,
      transferred: text.length,
      timestamp: DateTime.now(),
      status: TransferStatus.delivered,
      payload: _capClipboard(text),
    ));
    _lastIncomingClipboard = text.trim();
    _pendingClipboard = text;
    if (_lifecycle == AppLifecycleState.resumed) {
      await _flushPendingClipboard();
    }
    _emit('Clipboard received from ${device?.name ?? 'a device'}');
    await _notify(
      title: 'Clipboard updated',
      body: 'Text received from ${device?.name ?? fromName}',
    );
  }

  // --- messaging ---------------------------------------------------------

  /// Send a message to one device, or to several at once — more than one
  /// becomes a labelled group.
  Future<int> sendMessageToDevices(
    Iterable<String> deviceIds,
    String text,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _emit('Type a message first');
      return 0;
    }
    final devices = deviceIds
        .toSet()
        .map((id) => _trust.byId(id))
        .whereType<TrustedDevice>()
        .toList();
    if (devices.isEmpty) {
      _emit('Choose at least one device');
      return 0;
    }

    final group = _groupLabel(devices);
    var sent = 0;
    for (final device in devices) {
      try {
        final session = await _connect(device);
        await _client.sendMessage(
          session: session,
          text: trimmed,
          group: group,
        );
        sent++;
      } catch (error) {
        _emit(_reachError(device, error));
      }
    }

    if (sent > 0) {
      _addTransfer(TransferItem(
        id: _uuid.v4(),
        kind: TransferKind.message,
        direction: TransferDirection.outgoing,
        peerId: devices.length == 1 ? devices.first.deviceId : 'group',
        peerName: group ?? devices.first.name,
        title: trimmed.length > 60 ? '${trimmed.substring(0, 60)}…' : trimmed,
        bytes: trimmed.length,
        transferred: trimmed.length,
        timestamp: DateTime.now(),
        status: TransferStatus.delivered,
        payload: _capClipboard(trimmed),
        groupName: group,
      ));
    }
    return sent;
  }

  /// Universal messaging: everyone trusted.
  Future<int> sendMessageToAllTrusted(String text) =>
      sendMessageToDevices(_trust.devices.map((d) => d.deviceId), text);

  String? _groupLabel(List<TrustedDevice> devices) {
    if (devices.length < 2) return null;
    final names = devices.map((d) => d.name).toList()..sort();
    final joined = names.join(', ');
    return joined.length > 44 ? 'Group of ${names.length}' : 'Group · $joined';
  }

  @override
  Future<void> onMessageReceived({
    required String fromDeviceId,
    required String fromName,
    required String text,
    String? group,
  }) async {
    final device = _trust.byId(fromDeviceId);
    _addTransfer(TransferItem(
      id: _uuid.v4(),
      kind: TransferKind.message,
      direction: TransferDirection.incoming,
      peerId: fromDeviceId,
      peerName: group ?? device?.name ?? fromName,
      title: text.length > 60 ? '${text.substring(0, 60)}…' : text,
      bytes: text.length,
      transferred: text.length,
      timestamp: DateTime.now(),
      status: TransferStatus.delivered,
      payload: _capClipboard(text),
      groupName: group,
    ));
    _emit('Message from ${device?.name ?? fromName}');
    await _notify(
      title: 'Message from ${device?.name ?? fromName}',
      body: text.length > 120 ? '${text.substring(0, 120)}…' : text,
    );
  }

  // --- pairing requests --------------------------------------------------

  /// Ask a nearby device to show a pairing code, so the person can type it here
  /// instead of hunting for a code that was never displayed.
  Future<bool> requestPairingWith(NearbyPeer peer) async {
    try {
      // Our own single-use secret, which the other device calls back into
      // if it accepts.
      final payload = await beginPairing();
      await _client.requestPairing(
        host: peer.host,
        port: peer.port,
        payload: payload,
      );
      _emit('Asked ${peer.name} to confirm');
      return true;
    } catch (_) {
      _emit('Could not reach ${peer.name}');
      return false;
    }
  }

  @override
  Future<void> onPairRequest(PairingPayload requester) async {
    _pendingPairRequest = requester;
    notifyListeners();
    await _notify(
      title: '${requester.deviceName} wants to pair',
      body: 'Open Nearlink to accept',
    );
  }

  /// Accept a pending request. We call back into the requester's secret,
  /// which trusts us and hands over its identity for us to trust in return,
  /// so both sides end up paired with nothing typed by hand.
  Future<bool> acceptPairRequest() async {
    final requester = _pendingPairRequest;
    _pendingPairRequest = null;
    notifyListeners();
    if (requester == null) return false;
    return pairWithPayload(requester);
  }

  void declinePairRequest() {
    if (_pendingPairRequest == null) return;
    _pendingPairRequest = null;
    notifyListeners();
  }

  // --- introductions -----------------------------------------------------

  /// Vouch for two or more of our trusted devices so they can connect to
  /// each other. Every pair is asked separately, and a pair only connects
  /// when both sides say yes.
  Future<int> introduceDevices(Iterable<String> deviceIds) async {
    final devices = deviceIds
        .toSet()
        .map((id) => _trust.byId(id))
        .whereType<TrustedDevice>()
        .toList();
    if (devices.length < 2) {
      _emit('Pick at least two devices to introduce');
      return 0;
    }

    final me = _introPeerOfSelf();
    var arranged = 0;

    for (var i = 0; i < devices.length; i++) {
      for (var j = i + 1; j < devices.length; j++) {
        final first = devices[i];
        final second = devices[j];
        final firstPeer = _introPeerOf(first);
        final secondPeer = _introPeerOf(second);
        if (firstPeer == null || secondPeer == null) {
          _emit('${first.name} or ${second.name} is not reachable');
          continue;
        }

        final introId = _uuid.v4();
        final secret = base64Url.encode(SecureChannel.randomBytes(24));
        _introducedPairs[introId] = '${first.name} ↔ ${second.name}';

        final toFirst = await _sendIntroOffer(
          firstPeer,
          IntroOffer(
            introId: introId,
            secret: secret,
            introducer: me,
            counterpart: secondPeer,
          ),
        );
        final toSecond = await _sendIntroOffer(
          secondPeer,
          IntroOffer(
            introId: introId,
            secret: secret,
            introducer: me,
            counterpart: firstPeer,
          ),
        );

        if (toFirst && toSecond) {
          arranged++;
        } else {
          _introducedPairs.remove(introId);
          _emit('Could not reach ${toFirst ? second.name : first.name}');
        }
      }
    }

    if (arranged > 0) {
      _emit('Asked ${devices.length} devices to connect with each other');
    }
    return arranged;
  }

  Future<bool> _sendIntroOffer(IntroPeer to, IntroOffer offer) async {
    try {
      await _client.offerIntro(host: to.host, port: to.port, offer: offer);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> onIntroOffer(IntroOffer offer) async {
    _intros[offer.introId] = IntroSession(offer);
    notifyListeners();
    await _notify(
      title: '${offer.introducer.name} suggests connecting',
      body: 'With ${offer.counterpart.name}',
    );
  }

  /// Say yes. The shared secret is registered only now, so the pairing
  /// cannot complete unless the other device also consents.
  Future<void> acceptIntro() async {
    final session = pendingIntro;
    if (session == null) return;
    session.accepted = true;
    _registerIntroSecret(session);
    notifyListeners();
    await _broadcastIntroOutcome(session, accepted: true);
    await _maybeCompleteIntro(session);
  }

  /// Say no. That cancels the introduction for the other device too.
  Future<void> declineIntro() async {
    final session = pendingIntro;
    if (session == null) return;
    _intros.remove(session.offer.introId);
    session.declined = true;
    notifyListeners();
    _emit('Declined connecting with ${session.offer.counterpart.name}');
    await _broadcastIntroOutcome(session, accepted: false);
  }

  @override
  Future<void> onIntroAccepted({
    required String introId,
    required IntroPeer from,
  }) async {
    final session = _intros[introId];
    if (session == null) {
      final pair = _introducedPairs[introId];
      if (pair != null) _emit('$pair: ${from.name} agreed');
      return;
    }
    final allowed = <String>{
      session.offer.counterpart.deviceId,
      session.offer.introducer.deviceId,
    };
    if (!allowed.contains(from.deviceId)) return;
    session.counterpartAccepted = true;
    notifyListeners();
    await _maybeCompleteIntro(session);
  }

  @override
  Future<void> onIntroDeclined({
    required String introId,
    required IntroPeer from,
  }) async {
    final session = _intros[introId];
    if (session == null) {
      final pair = _introducedPairs[introId];
      if (pair != null) _emit('$pair: ${from.name} declined');
      return;
    }
    final allowed = <String>{
      session.offer.counterpart.deviceId,
      session.offer.introducer.deviceId,
    };
    if (!allowed.contains(from.deviceId)) return;
    // One refusal cancels it here as well, even if we already said yes.
    _intros.remove(introId);
    session.declined = true;
    notifyListeners();
    _emit('${from.name} declined — connecting cancelled');
  }

  /// Register the introducer's shared secret as something the other device
  /// may pair with. Done on consent, so a one-sided pairing is impossible.
  void _registerIntroSecret(IntroSession session) {
    final other = session.offer.counterpart;
    _server.offerPairing(PairingPayload(
      deviceId: other.deviceId,
      deviceName: other.name,
      platform: other.platform,
      model: other.model,
      agreementKey: other.fingerprint,
      identityKey: '',
      fingerprint: other.fingerprint,
      host: other.host,
      port: other.port,
      token: session.offer.secret,
      pin: session.offer.secret,
      createdAt: DateTime.now(),
    ));
  }

  Future<void> _broadcastIntroOutcome(
    IntroSession session, {
    required bool accepted,
  }) async {
    final me = _introPeerOfSelf();
    for (final peer in <IntroPeer>[
      session.offer.counterpart,
      session.offer.introducer,
    ]) {
      try {
        await _client.sendIntroOutcome(
          host: peer.host,
          port: peer.port,
          introId: session.offer.introId,
          from: me,
          accepted: accepted,
        );
      } catch (_) {
        // The other side will simply not hear about it; nothing to undo.
      }
    }
  }

  /// Pair once both sides have agreed. Only the device with the lower id
  /// makes the call, so it is not attempted twice.
  Future<void> _maybeCompleteIntro(IntroSession session) async {
    if (!session.readyToPair) return;
    final other = session.offer.counterpart;
    if (_identity.deviceId.compareTo(other.deviceId) >= 0) return;

    session.completed = true;
    notifyListeners();
    try {
      final device = await _client.pairWith(
        host: other.host,
        port: other.port,
        secret: session.offer.secret,
        name: deviceName,
        platform: _currentPlatform().name,
        model: deviceModel,
      );
      await _adoptPairedDevice(device);
      _emit('${other.name} is now a trusted device');
    } catch (_) {
      session.completed = false;
      _emit('Could not connect with ${other.name}');
    }
  }

  IntroPeer _introPeerOfSelf() => IntroPeer(
        deviceId: _identity.deviceId,
        name: deviceName,
        platform: _currentPlatform(),
        model: deviceModel,
        host: '0.0.0.0',
        port: _server.port,
        fingerprint: _identity.fingerprint,
      );

  IntroPeer? _introPeerOf(TrustedDevice device) {
    final address = _addressFor(device);
    if (address == null) return null;
    return IntroPeer(
      deviceId: device.deviceId,
      name: device.name,
      platform: device.platform,
      model: device.model,
      host: address.host,
      port: address.port,
      fingerprint: device.fingerprint,
    );
  }

  // --- transfer bookkeeping ---------------------------------------------

  void _addTransfer(TransferItem item) {
    _transfers.insert(0, item);
    if (_transfers.length > HistoryStore.maxEntries) {
      _transfers = _transfers.take(HistoryStore.maxEntries).toList();
    }
    _history.save(_transfers);
    notifyListeners();
  }

  void _updateTransfer(
    String id,
    TransferItem Function(TransferItem) transform,
  ) {
    final index = _transfers.indexWhere((t) => t.id == id);
    if (index < 0) return;
    _transfers[index] = transform(_transfers[index]);
    _history.save(_transfers);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _transfers = <TransferItem>[];
    await _history.save(_transfers);
    notifyListeners();
  }

  // --- misc --------------------------------------------------------------

  Future<void> setDeviceName(String value) async {
    await _settings.setDeviceName(value);
    notifyListeners();
  }

  Future<void> setAutoAcceptTrusted(bool value) async {
    await _settings.setAutoAcceptTrusted(value);
    notifyListeners();
  }

  /// True while text has arrived but could not be put on the clipboard yet.
  bool get hasPendingClipboard => _pendingClipboard != null;

  /// Apply anything received while we were backgrounded. Called on resume.
  Future<void> _flushPendingClipboard() async {
    final text = _pendingClipboard;
    if (text == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      _pendingClipboard = null;
      _emit('Clipboard updated from your other device');
    } catch (_) {
      // Still blocked; try again next time we come back.
    }
  }

  /// Empty this device's system clipboard.
  Future<void> clearSystemClipboard() async {
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
      _pendingClipboard = null;
      _lastLocalClipboard = null;
      _emit('Clipboard cleared');
    } catch (_) {
      _emit('Could not clear the clipboard');
    }
    notifyListeners();
  }

  /// Remove clipboard entries from the history, leaving files and messages.
  Future<void> clearClipboardHistory() async {
    _transfers = _transfers
        .where((t) => t.kind != TransferKind.clipboard)
        .toList();
    await _history.save(_transfers);
    _emit('Clipboard history cleared');
    notifyListeners();
  }

  bool get notificationsEnabled => _settings.notificationsEnabled;

  Future<void> setNotificationsEnabled(bool value) async {
    await _settings.setNotificationsEnabled(value);
    if (value) await NotificationService.requestPermission();
    _emit(value ? 'Notifications on' : 'Notifications off');
    notifyListeners();
  }

  Future<void> _initNotifications() async {
    await NotificationService.init();
    if (notificationsEnabled) {
      await NotificationService.requestPermission();
    }
  }

  /// True when the app is not on screen, so a system notification is the
  /// only way the person will notice.
  bool get _isBackgrounded =>
      _lifecycle == AppLifecycleState.paused ||
      _lifecycle == AppLifecycleState.hidden;

  Future<void> _notify({required String title, required String body}) async {
    if (!notificationsEnabled || !_isBackgrounded) return;
    await NotificationService.show(title: title, body: body);
  }

  bool get keepAliveInBackground => _settings.keepAliveInBackground;

  /// Whether this platform can hold itself awake in the background at all.
  bool get canKeepAliveInBackground => BackgroundKeeper.isSupported;

  Future<void> setKeepAliveInBackground(bool value) async {
    await _settings.setKeepAliveInBackground(value);
    await _syncBackgroundKeeper();
    _emit(value
        ? 'Nearlink will keep receiving while minimised'
        : 'Nearlink will pause when minimised');
    notifyListeners();
  }

  /// Android freezes backgrounded processes, which stops receiving, discovery
  /// and clipboard sync. A foreground service keeps the process alive.
  Future<void> _syncBackgroundKeeper() async {
    if (!BackgroundKeeper.isSupported) return;
    if (keepAliveInBackground) {
      await BackgroundKeeper.start(
        title: 'Nearlink is ready',
        text: 'Can receive files, messages and clipboard from your devices',
      );
    } else {
      await BackgroundKeeper.stop();
    }
  }

  bool get autoSyncClipboard => _settings.autoSyncClipboard;

  Future<void> setAutoSyncClipboard(bool value) async {
    await _settings.setAutoSyncClipboard(value);
    _syncClipboardWatcher();
    _emit(value
        ? 'Clipboard sync on — copies go to every trusted device'
        : 'Clipboard sync off');
    notifyListeners();
  }

  void _syncClipboardWatcher() {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
    if (!autoSyncClipboard) return;
    _clipboardTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollClipboard()),
    );
  }

  /// Watch the local clipboard and broadcast changes. Loops are avoided by
  /// remembering what we last sent and what we last received.
  Future<void> _pollClipboard() async {
    if (!autoSyncClipboard || _trust.devices.isEmpty) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) return;
      if (text == _lastLocalClipboard) return;
      if (text == _lastIncomingClipboard) {
        _lastLocalClipboard = text;
        return;
      }
      _lastLocalClipboard = text;
      await sendClipboardToAllTrusted(text, quiet: true);
    } catch (_) {
      // Clipboard read can be blocked by the platform; skip this tick.
    }
  }

  /// Clipboard history keeps the text so entries can be re-copied, but only
  /// up to a sane size.
  String _capClipboard(String text) =>
      text.length > 8192 ? text.substring(0, 8192) : text;

  void _emit(String message) {
    if (!_messages.isClosed) _messages.add(message);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_flushPendingClipboard());
      unawaited(_syncBackgroundKeeper());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_syncBackgroundKeeper());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BackgroundKeeper.stop();
    _clipboardTimer?.cancel();
    _peerSub?.cancel();
    _discovery.dispose();
    _server.stop();
    _client.dispose();
    _messages.close();
    super.dispose();
  }
}
