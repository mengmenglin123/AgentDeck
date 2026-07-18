import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-local terminal command history (never uploaded).
class TerminalHistoryStore {
  TerminalHistoryStore({this.maxEntries = 50});

  final int maxEntries;
  static const _k = 'huanhermes.term_history.v1';

  Future<List<String>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw == null || raw.isEmpty) return [];
    try {
      final v = jsonDecode(raw);
      if (v is! List) return [];
      return v
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> push(String command) async {
    final t = command.trimRight();
    if (t.isEmpty || t == '\u0003') return;
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((e) => e == t);
    list.insert(0, t);
    while (list.length > maxEntries) {
      list.removeLast();
    }
    await p.setString(_k, jsonEncode(list));
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_k);
  }
}
