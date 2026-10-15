import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transfer_item.dart';

/// Persists recent transfer activity, capped so it never grows unbounded.
class HistoryStore {
  HistoryStore(this._prefs);

  final SharedPreferences _prefs;
  static const String _key = 'nearlink_transfer_history_v1';
  static const int maxEntries = 60;

  List<TransferItem> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <TransferItem>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TransferItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <TransferItem>[];
    }
  }

  Future<void> save(List<TransferItem> items) async {
    final trimmed = items.take(maxEntries).toList();
    await _prefs.setString(
      _key,
      jsonEncode(trimmed.map((i) => i.toJson()).toList()),
    );
  }
}
