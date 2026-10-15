import 'dart:async';

import '../models/device.dart';

/// Advertises this device on the local network and streams the peers it sees.
///
/// Abstracted so the app can run against real mDNS on device, and against a
/// stub in tests.
abstract class DiscoveryService {
  /// Peers currently visible. Emits the full current set on every change.
  Stream<List<NearbyPeer>> get peers;

  /// Start advertising this device and browsing for others.
  Future<void> start({
    required String deviceId,
    required String deviceName,
    required DevicePlatform platform,
    required int port,
    required String fingerprint,
    required String agreementKey,
    required String model,
  });

  /// Stop advertising and browsing, and release the socket.
  Future<void> stop();

  /// True once this device has successfully registered its advertisement.
  bool get isAdvertising;

  /// Number of raw mDNS services currently visible, before any filtering.
  /// Useful for telling "nothing on the network" apart from "we dropped it".
  int get rawServiceCount;

  void dispose();
}
