import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the Android process alive while the app is minimised.
///
/// Android freezes backgrounded processes, which stops the receiving server,
/// mDNS discovery and the clipboard watcher. A foreground service with a
/// persistent notification is the platform-sanctioned way to stay alive, so
/// this talks to one over a method channel.
///
/// It is a no-op everywhere except Android, and it fails quietly if the native
/// side has not been added to the project yet.
class BackgroundKeeper {
  BackgroundKeeper._();

  static const MethodChannel _channel = MethodChannel('nearlink/background');

  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  static Future<void> start({
    required String title,
    required String text,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('start', <String, String>{
        'title': title,
        'text': text,
      });
    } on MissingPluginException {
      // The native service has not been added to android/ yet — the app still
      // works in the foreground, so this is not fatal.
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } on MissingPluginException {
      // Nothing to stop.
    } catch (_) {}
  }
}
