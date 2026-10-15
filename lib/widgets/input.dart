import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A consistent text-field decoration used across the app, applied inline so
/// the app does not depend on ThemeData fields that have changed shape between
/// Flutter releases.
InputDecoration nearlinkInput({String? labelText, String? hintText}) {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(NearlinkColors.line),
    enabledBorder: border(NearlinkColors.line),
    focusedBorder: border(NearlinkColors.accent, 1.6),
  );
}
