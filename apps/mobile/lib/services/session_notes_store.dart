import 'package:shared_preferences/shared_preferences.dart';

/// Device-local notes keyed by session_key (never uploaded).
class SessionNotesStore {
  static const _k = 'huanhermes.session_notes.v1';

  Future<Map<String, String>> all() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_k) ?? const [];
    final out = <String, String>{};
    for (final row in raw) {
      final i = row.indexOf('\u0001');
      if (i <= 0) continue;
      out[row.substring(0, i)] = row.substring(i + 1);
    }
    return out;
  }

  Future<String?> get(String sessionKey) async {
    final m = await all();
    return m[sessionKey];
  }

  Future<void> set(String sessionKey, String note) async {
    final m = await all();
    final t = note.trim();
    if (t.isEmpty) {
      m.remove(sessionKey);
    } else {
      m[sessionKey] = t;
    }
    final p = await SharedPreferences.getInstance();
    final rows = m.entries.map((e) => '${e.key}\u0001${e.value}').toList();
    await p.setStringList(_k, rows);
  }

  Future<void> remove(String sessionKey) => set(sessionKey, '');
}
