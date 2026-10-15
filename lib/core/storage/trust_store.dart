import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';

/// Persists the set of devices this device trusts (has paired with).
class TrustStore {
  TrustStore(this._prefs);

  final SharedPreferences _prefs;
  static const String _key = 'nearlink_trusted_devices_v1';
  static const String _pendingKey = 'nearlink_pending_revocations_v1';

  final List<TrustedDevice> _devices = <TrustedDevice>[];
  final List<String> _pendingRevocations = <String>[];

  /// Devices we removed while they were offline and still need to tell.
  List<String> get pendingRevocations => List.unmodifiable(_pendingRevocations);

  List<TrustedDevice> get devices => List.unmodifiable(_devices);

  int get count => _devices.length;

  void load() {
    _devices.clear();
    _pendingRevocations.clear();
    final pending = _prefs.getStringList(_pendingKey);
    if (pending != null) _pendingRevocations.addAll(pending);
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final entry in list) {
        _devices.add(TrustedDevice.fromJson(entry as Map<String, dynamic>));
      }
    } catch (_) {
      _devices.clear();
    }
  }

  bool contains(String deviceId) =>
      _devices.any((d) => d.deviceId == deviceId);

  TrustedDevice? byId(String deviceId) {
    for (final d in _devices) {
      if (d.deviceId == deviceId) return d;
    }
    return null;
  }

  Future<void> add(TrustedDevice device) async {
    final index = _devices.indexWhere((d) => d.deviceId == device.deviceId);
    if (index >= 0) {
      _devices[index] = device;
    } else {
      _devices.add(device);
    }
    await _persist();
  }

  Future<void> remove(String deviceId) async {
    _devices.removeWhere((d) => d.deviceId == deviceId);
    await _persist();
  }

  Future<void> touch(String deviceId) async {
    final index = _devices.indexWhere((d) => d.deviceId == deviceId);
    if (index < 0) return;
    _devices[index] = _devices[index].copyWith(lastSeen: DateTime.now());
    await _persist();
  }

  Future<void> addPendingRevocation(String deviceId) async {
    if (_pendingRevocations.contains(deviceId)) return;
    _pendingRevocations.add(deviceId);
    await _prefs.setStringList(_pendingKey, _pendingRevocations);
  }

  Future<void> clearPendingRevocation(String deviceId) async {
    if (!_pendingRevocations.remove(deviceId)) return;
    await _prefs.setStringList(_pendingKey, _pendingRevocations);
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _key,
      jsonEncode(_devices.map((d) => d.toJson()).toList()),
    );
  }
}
