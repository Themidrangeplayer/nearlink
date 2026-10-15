import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import '../models/device.dart';
import '../protocol/protocol.dart';
import 'discovery_service.dart';

/// Real mDNS/DNS-SD discovery backed by the `nsd` plugin.
///
/// `nsd` covers Android, iOS, macOS, Windows and Linux, which is exactly the
/// platform set Nearlink targets.
///
/// Two platform quirks shape this class:
///
/// * TXT values are raw bytes (`Uint8List`), so we UTF-8 encode on advertise
///   and decode on read.
/// * TXT records are *not* delivered reliably by every platform backend, so a
///   service is surfaced on host + port alone. Identity details are filled in
///   afterwards by querying the peer's `/info` endpoint (see `AppState`).
///   Dropping services for a missing TXT record is what made devices invisible
///   on macOS even though `dns-sd` could see them.
class NsdDiscoveryService implements DiscoveryService {
  NsdDiscoveryService();

  final StreamController<List<NearbyPeer>> _controller =
      StreamController<List<NearbyPeer>>.broadcast();

  nsd.Registration? _registration;
  nsd.Discovery? _discovery;

  @override
  Stream<List<NearbyPeer>> get peers => _controller.stream;

  @override
  bool get isAdvertising => _registration != null;

  @override
  int get rawServiceCount => _discovery?.services.length ?? 0;

  static Uint8List _bytes(String value) =>
      Uint8List.fromList(utf8.encode(value));

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
    final service = nsd.Service(
      name: deviceName,
      type: NearlinkProtocol.serviceType,
      port: port,
      txt: <String, Uint8List>{
        NearlinkProtocol.txtId: _bytes(deviceId),
        NearlinkProtocol.txtName: _bytes(deviceName),
        NearlinkProtocol.txtPlatform: _bytes(platform.name),
        NearlinkProtocol.txtModel: _bytes(model),
        NearlinkProtocol.txtFingerprint: _bytes(fingerprint),
        NearlinkProtocol.txtAgreementKey: _bytes(agreementKey),
        NearlinkProtocol.txtVersion: _bytes(NearlinkProtocol.version),
      },
    );

    _registration = await nsd.register(service);

    _discovery = await nsd.startDiscovery(NearlinkProtocol.serviceType);
    _discovery!.addListener(_emit);
    _emit();
  }

  void _emit() {
    final discovery = _discovery;
    if (discovery == null || _controller.isClosed) return;

    final now = DateTime.now();
    final peers = <NearbyPeer>[];
    for (final service in discovery.services) {
      final peer = _toPeer(service, now);
      if (peer != null) peers.add(peer);
    }
    _controller.add(peers);
  }

  NearbyPeer? _toPeer(nsd.Service service, DateTime now) {
    // Host and port are the only things we insist on; everything else is a
    // bonus that we top up over HTTP later.
    final host = _hostOf(service);
    final port = service.port;
    if (host == null || port == null || port == 0) return null;

    final txt = service.txt;
    String? read(String key) {
      final value = txt?[key];
      return value == null ? null : utf8.decode(value);
    }

    final fallbackName = service.name ?? 'Nearlink device';
    final id = read(NearlinkProtocol.txtId) ?? fallbackName;

    return NearbyPeer(
      deviceId: id,
      name: read(NearlinkProtocol.txtName) ?? fallbackName,
      platform: platformFromString(read(NearlinkProtocol.txtPlatform)),
      model: read(NearlinkProtocol.txtModel) ?? '',
      host: host,
      port: port,
      fingerprint: read(NearlinkProtocol.txtFingerprint) ?? '',
      agreementKey: read(NearlinkProtocol.txtAgreementKey) ?? '',
      discoveredAt: now,
    );
  }

  String? _hostOf(nsd.Service service) {
    final addresses = service.addresses;
    if (addresses != null && addresses.isNotEmpty) {
      // Prefer IPv4 for maximum compatibility across platforms.
      for (final address in addresses) {
        if (address.type == InternetAddressType.IPv4) return address.address;
      }
      return addresses.first.address;
    }
    return service.host;
  }

  @override
  Future<void> stop() async {
    final discovery = _discovery;
    if (discovery != null) {
      discovery.removeListener(_emit);
      await nsd.stopDiscovery(discovery);
      _discovery = null;
    }
    final registration = _registration;
    if (registration != null) {
      await nsd.unregister(registration);
      _registration = null;
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}
