import 'package:flutter/material.dart';

import '../core/models/device.dart';

IconData platformIcon(DevicePlatform platform) {
  switch (platform) {
    case DevicePlatform.android:
      return Icons.smartphone;
    case DevicePlatform.ios:
      return Icons.phone_iphone;
    case DevicePlatform.windows:
      return Icons.laptop_windows;
    case DevicePlatform.macos:
      return Icons.laptop_mac;
    case DevicePlatform.linux:
      return Icons.computer;
    case DevicePlatform.unknown:
      return Icons.devices_other;
  }
}

Color platformTint(DevicePlatform platform) {
  switch (platform) {
    case DevicePlatform.android:
      return const Color(0xFFE7EBFF);
    case DevicePlatform.ios:
      return const Color(0xFFE7EBFF);
    case DevicePlatform.windows:
      return const Color(0xFFFFF2DB);
    case DevicePlatform.macos:
      return const Color(0xFFE4F6EF);
    case DevicePlatform.linux:
      return const Color(0xFFF0E9FB);
    case DevicePlatform.unknown:
      return const Color(0xFFEEF2EE);
  }
}
