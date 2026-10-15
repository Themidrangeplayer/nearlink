import 'package:shared_preferences/shared_preferences.dart';

/// Small persisted user settings.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _kDeviceName = 'nearlink.deviceName';
  static const String _kDiscovery = 'nearlink.discoveryEnabled';
  static const String _kAutoAccept = 'nearlink.autoAccept';
  static const String _kAccount = 'nearlink.accountLabel';
  static const String _kDeviceModel = 'nearlink.deviceModel';
  static const String _kKeepAlive = 'nearlink.keepAliveInBackground';
  static const String _kNotifications = 'nearlink.notificationsEnabled';
  static const String _kAutoSyncClipboard = 'nearlink.autoSyncClipboard';

  String? get deviceName => _prefs.getString(_kDeviceName);

  Future<void> setDeviceName(String value) =>
      _prefs.setString(_kDeviceName, value);

  bool get discoveryEnabled => _prefs.getBool(_kDiscovery) ?? true;

  Future<void> setDiscoveryEnabled(bool value) =>
      _prefs.setBool(_kDiscovery, value);

  bool get autoAcceptTrusted => _prefs.getBool(_kAutoAccept) ?? true;

  Future<void> setAutoAcceptTrusted(bool value) =>
      _prefs.setBool(_kAutoAccept, value);

  /// When on, local clipboard changes are broadcast to every trusted device.
  bool get autoSyncClipboard => _prefs.getBool(_kAutoSyncClipboard) ?? false;

  Future<void> setAutoSyncClipboard(bool value) =>
      _prefs.setBool(_kAutoSyncClipboard, value);

  /// Short device descriptor, e.g. "Nothing A001" or "MacBookAir10,1".
  String? get deviceModel => _prefs.getString(_kDeviceModel);

  Future<void> setDeviceModel(String value) =>
      _prefs.setString(_kDeviceModel, value);

  /// Android only: keep the process alive with a foreground service.
  bool get keepAliveInBackground => _prefs.getBool(_kKeepAlive) ?? true;

  Future<void> setKeepAliveInBackground(bool value) =>
      _prefs.setBool(_kKeepAlive, value);

  /// Notify when something arrives and the app is not in the foreground.
  bool get notificationsEnabled =>
      _prefs.getBool(_kNotifications) ?? true;

  Future<void> setNotificationsEnabled(bool value) =>
      _prefs.setBool(_kNotifications, value);

  String get accountLabel => _prefs.getString(_kAccount) ?? 'Personal space';

  Future<void> setAccountLabel(String value) =>
      _prefs.setString(_kAccount, value);
}
