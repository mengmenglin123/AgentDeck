import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local prompt favorites + recent history (device-only; never uploaded).
/// Inspired by common remote-console UX (favorites + recents) — in-repo only.
class PromptHistoryStore {
  PromptHistoryStore({this.maxRecent = 40, this.maxFavorites = 30});

  final int maxRecent;
  final int maxFavorites;

  static const _kRecent = 'huan.prompt.recent.v1';
  static const _kFav = 'huan.prompt.favorites.v1';

  Future<List<String>> recent() async {
    final p = await SharedPreferences.getInstance();
    return _decode(p.getString(_kRecent));
  }

  Future<List<String>> favorites() async {
    final p = await SharedPreferences.getInstance();
    return _decode(p.getString(_kFav));
  }

  Future<void> addRecent(String text) async {
    final t = text.trim();
    if (t.isEmpty || t.startsWith('/')) return;
    final p = await SharedPreferences.getInstance();
    final list = _decode(p.getString(_kRecent));
    list.removeWhere((e) => e == t);
    list.insert(0, t);
    while (list.length > maxRecent) {
      list.removeLast();
    }
    await p.setString(_kRecent, jsonEncode(list));
  }

  Future<void> toggleFavorite(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final list = _decode(p.getString(_kFav));
    if (list.contains(t)) {
      list.remove(t);
    } else {
      list.insert(0, t);
      while (list.length > maxFavorites) {
        list.removeLast();
      }
    }
    await p.setString(_kFav, jsonEncode(list));
  }

  Future<bool> isFavorite(String text) async {
    final list = await favorites();
    return list.contains(text.trim());
  }

  Future<void> removeFavorite(String text) async {
    final p = await SharedPreferences.getInstance();
    final list = _decode(p.getString(_kFav));
    list.remove(text.trim());
    await p.setString(_kFav, jsonEncode(list));
  }

  Future<void> removeRecent(String text) async {
    final p = await SharedPreferences.getInstance();
    final list = _decode(p.getString(_kRecent));
    list.remove(text.trim());
    await p.setString(_kRecent, jsonEncode(list));
  }

  Future<void> clearRecent() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kRecent);
  }

  Future<void> clearFavorites() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kFav);
  }

  List<String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final v = jsonDecode(raw);
      if (v is! List) return [];
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }
}
