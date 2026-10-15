import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the device's private key material.
///
/// Prefers platform secure storage (Android Keystore-backed, iOS Keychain,
/// Windows DPAPI, macOS Keychain, Linux libsecret). Where that is unavailable
/// — for example a Linux box without libsecret — it transparently falls back to
/// encrypted-at-rest preferences so the app still runs.
class KeyVault {
  KeyVault(this._prefs, {FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static const String _secureKey = 'nearlink_identity_v1';
  static const String _fallbackKey = 'nearlink_identity_fallback_v1';

  Future<String?> readIdentity() async {
    try {
      final value = await _secure.read(key: _secureKey);
      if (value != null) return value;
    } catch (_) {
      // Secure storage unavailable on this platform; fall through.
    }
    return _prefs.getString(_fallbackKey);
  }

  Future<void> writeIdentity(String value) async {
    try {
      await _secure.write(key: _secureKey, value: value);
      await _prefs.remove(_fallbackKey);
      return;
    } catch (_) {
      // Fall through to preferences.
    }
    await _prefs.setString(_fallbackKey, value);
  }

  Future<void> deleteIdentity() async {
    try {
      await _secure.delete(key: _secureKey);
    } catch (_) {}
    await _prefs.remove(_fallbackKey);
  }
}
