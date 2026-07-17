import 'package:shared_preferences/shared_preferences.dart';

/// Device-local recently opened session keys (never uploaded).
class SessionRecentsStore {
  static const _k = 'huanhermes.session_recents.v1';
  static const _max = 40;

  Future<List<String>> orderedKeys() async {
    final p = await SharedPreferences.getInstance();
    return List<String>.from(p.getStringList(_k) ?? const []);
  }

  Future<Map<String, int>> ranks() async {
    final keys = await orderedKeys();
    final out = <String, int>{};
    for (var i = 0; i < keys.length; i++) {
      out[keys[i]] = i; // 0 = most recent
    }
    return out;
  }

  Future<void> touch(String sessionKey) async {
    final k = sessionKey.trim();
    if (k.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final list = List<String>.from(p.getStringList(_k) ?? const []);
    list.remove(k);
    list.insert(0, k);
    if (list.length > _max) {
      list.removeRange(_max, list.length);
    }
    await p.setStringList(_k, list);
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_k);
  }
}
