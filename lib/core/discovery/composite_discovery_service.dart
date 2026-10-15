import 'dart:async';

import '../models/device.dart';
import 'discovery_service.dart';

/// Runs several discovery mechanisms at once and merges what they find.
///
/// Nearlink uses this with mDNS and the UDP broadcast beacon together: whichever
/// one works on a given network wins, and a failure in one never stops the
/// other. A peer seen by both is kept once, preferring whichever copy carries
/// more detail.
class CompositeDiscoveryService implements DiscoveryService {
  CompositeDiscoveryService(this._children);

  final List<DiscoveryService> _children;

  final StreamController<List<NearbyPeer>> _controller =
      StreamController<List<NearbyPeer>>.broadcast();
  final Map<String, NearbyPeer> _merged = <String, NearbyPeer>{};
  final Map<DiscoveryService, List<NearbyPeer>> _latest =
      <DiscoveryService, List<NearbyPeer>>{};

  @override
  Stream<List<NearbyPeer>> get peers => _controller.stream;

  @override
  bool get isAdvertising => _children.any((child) => child.isAdvertising);

  @override
  int get rawServiceCount => _merged.length;

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
    for (final child in _children) {
      child.peers.listen((peers) {
        _latest[child] = peers;
        _rebuild();
      });
    }

    // Start each mechanism independently and do not wait for any of them.
    // A platform plugin that never answers must not hold up the others, and
    // must never hold up the app's startup.
    for (final child in _children) {
      unawaited(_startChild(
        child,
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
        port: port,
        fingerprint: fingerprint,
        agreementKey: agreementKey,
        model: model,
      ));
    }
  }

  Future<void> _startChild(
    DiscoveryService child, {
    required String deviceId,
    required String deviceName,
    required DevicePlatform platform,
    required int port,
    required String fingerprint,
    required String agreementKey,
    required String model,
  }) async {
    try {
      await child
          .start(
            deviceId: deviceId,
            deviceName: deviceName,
            platform: platform,
            port: port,
            fingerprint: fingerprint,
            agreementKey: agreementKey,
            model: model,
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // This mechanism is unavailable; the others carry on.
    }
  }

  void _rebuild() {
    _merged.clear();
    for (final peers in _latest.values) {
      for (final peer in peers) {
        final existing = _merged[peer.deviceId];
        if (existing == null) {
          _merged[peer.deviceId] = peer;
          continue;
        }
        final existingRicher =
            existing.fingerprint.isNotEmpty && existing.agreementKey.isNotEmpty;
        final peerRicher =
            peer.fingerprint.isNotEmpty && peer.agreementKey.isNotEmpty;
        if (!existingRicher && peerRicher) {
          _merged[peer.deviceId] = peer;
        } else if (existingRicher == peerRicher &&
            peer.discoveredAt.isAfter(existing.discoveredAt)) {
          _merged[peer.deviceId] = peer;
        }
      }
    }
    if (!_controller.isClosed) {
      _controller.add(_merged.values.toList());
    }
  }

  @override
  Future<void> stop() async {
    for (final child in _children) {
      try {
        await child.stop();
      } catch (_) {}
    }
    _latest.clear();
    _merged.clear();
  }

  @override
  void dispose() {
    for (final child in _children) {
      child.dispose();
    }
    _controller.close();
  }
}
