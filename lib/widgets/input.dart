import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A consistent text-field decoration used across the app, applied inline so
/// the app does not depend on ThemeData fields that have changed shape between
/// Flutter releases.
InputDecoration nearlinkInput({
  String? labelText,
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? helperText,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,
    hintStyle: const TextStyle(color: Color(0xFF9AA09C), fontSize: 13.5),
    labelStyle: const TextStyle(color: NearlinkColors.muted, fontSize: 13.5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: border(const Color(0xFFDCE2DC)),
    enabledBorder: border(const Color(0xFFDCE2DC)),
    focusedBorder: border(NearlinkColors.accent, 1.8),
  );
}
