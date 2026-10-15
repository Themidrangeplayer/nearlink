import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/device.dart';
import '../protocol/protocol.dart';
import 'discovery_service.dart';

/// Discovery that does not depend on mDNS at all.
///
/// Each device broadcasts a small JSON beacon on a fixed UDP port and listens
/// for everyone else's. It is pure Dart, so it behaves the same on Android, iOS
/// and desktop, and it avoids the platform multicast handling that made mDNS
/// browsing unreliable on Android — devices could advertise but never see each
/// other.
class BroadcastDiscoveryService implements DiscoveryService {
  BroadcastDiscoveryService({this.port = NearlinkProtocol.broadcastPort});

  final int port;

  final StreamController<List<NearbyPeer>> _controller =
      StreamController<List<NearbyPeer>>.broadcast();
  final Map<String, NearbyPeer> _peers = <String, NearbyPeer>{};

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Timer? _pruneTimer;
  Map<String, dynamic>? _self;

  @override
  Stream<List<NearbyPeer>> get peers => _controller.stream;

  @override
  bool get isAdvertising => _socket != null;

  @override
  int get rawServiceCount => _peers.length;

  @override
  Future<void> start({
    required String deviceId,
    required String deviceName,
    required DevicePlatform platform,
    required int port,
    required String fingerprint,
    required String agreementKey,
    required String model,
  }) async {
    _self = <String, dynamic>{
      NearlinkProtocol.txtId: deviceId,
      NearlinkProtocol.txtName: deviceName,
      NearlinkProtocol.txtPlatform: platform.name,
      NearlinkProtocol.txtModel: model,
      NearlinkProtocol.txtFingerprint: fingerprint,
      NearlinkProtocol.txtAgreementKey: agreementKey,
      'port': port,
      'v': NearlinkProtocol.version,
    };

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      this.port,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    _socket = socket;

    socket.listen(_onEvent, onError: (Object _) {}, cancelOnError: false);

    _beaconTimer = Timer.periodic(
      const Duration(seconds: NearlinkProtocol.beaconIntervalSeconds),
      (_) => _beacon(),
    );
    _pruneTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _prune(),
    );
    _beacon();
    _emit();
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;
    try {
      final decoded =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      _absorb(decoded, datagram.address.address);
    } catch (_) {
      // Not one of ours; ignore.
    }
  }

  void _absorb(Map<String, dynamic> json, String host) {
    final id = json[NearlinkProtocol.txtId] as String?;
    final peerPort = json['port'] as int?;
    if (id == null || peerPort == null || peerPort == 0) return;
    if (id == _self?[NearlinkProtocol.txtId]) return;

    _peers[id] = NearbyPeer(
      deviceId: id,
      name: json[NearlinkProtocol.txtName] as String? ?? 'Nearlink device',
      platform:
          platformFromString(json[NearlinkProtocol.txtPlatform] as String?),
      model: json[NearlinkProtocol.txtModel] as String? ?? '',
      host: host,
      port: peerPort,
      fingerprint: json[NearlinkProtocol.txtFingerprint] as String? ?? '',
      agreementKey:
          json[NearlinkProtocol.txtAgreementKey] as String? ?? '',
      discoveredAt: DateTime.now(),
    );
    _emit();
  }

  void _beacon() {
    final socket = _socket;
    final self = _self;
    if (socket == null || self == null) return;
    final data = Uint8List.fromList(utf8.encode(jsonEncode(self)));
    try {
      socket.send(data, InternetAddress('255.255.255.255'), port);
    } catch (_) {
      // Some networks reject limited broadcast; the peers we already know about
      // stay reachable via their last address.
    }
  }

  void _prune() {
    final cutoff = DateTime.now()
        .subtract(const Duration(seconds: NearlinkProtocol.peerTimeoutSeconds));
    final before = _peers.length;
    _peers.removeWhere((_, peer) => peer.discoveredAt.isBefore(cutoff));
    if (_peers.length != before) _emit();
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(_peers.values.toList());
  }

  @override
  Future<void> stop() async {
    _beaconTimer?.cancel();
    _pruneTimer?.cancel();
    _beaconTimer = null;
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
    _peers.clear();
  }

  @override
  void dispose() {
    _controller.close();
  }
}
