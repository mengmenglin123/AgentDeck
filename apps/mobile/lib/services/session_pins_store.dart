import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local session pin/favorite keys (device-only).
class SessionPinsStore {
  static const _k = 'huanhermes.session_pins.v1';

  Future<Set<String>> pins() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final list = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      return list.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<bool> isPinned(String sessionKey) async {
    final s = await pins();
    return s.contains(sessionKey);
  }

  Future<void> toggle(String sessionKey) async {
    final p = await SharedPreferences.getInstance();
    final s = await pins();
    if (s.contains(sessionKey)) {
      s.remove(sessionKey);
    } else {
      s.add(sessionKey);
    }
    await p.setString(_k, jsonEncode(s.toList()));
  }

  Future<void> setPinned(String sessionKey, bool pinned) async {
    final p = await SharedPreferences.getInstance();
    final s = await pins();
    if (pinned) {
      s.add(sessionKey);
    } else {
      s.remove(sessionKey);
    }
    await p.setString(_k, jsonEncode(s.toList()));
  }
}
