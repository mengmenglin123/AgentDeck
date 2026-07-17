import 'package:shared_preferences/shared_preferences.dart';

/// Device-local chat composer drafts (never uploaded). Keyed by session_key.
class ChatDraftStore {
  static const _prefix = 'huanhermes.chat_draft.v1:';

  Future<String?> load(String sessionKey) async {
    final k = sessionKey.trim();
    if (k.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    return p.getString('$_prefix$k');
  }

  Future<void> save(String sessionKey, String text) async {
    final k = sessionKey.trim();
    if (k.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final t = text; // keep whitespace drafts
    if (t.trim().isEmpty) {
      await p.remove('$_prefix$k');
      return;
    }
    // Cap size to avoid bloating prefs
    final clipped = t.length > 8000 ? t.substring(0, 8000) : t;
    await p.setString('$_prefix$k', clipped);
  }

  Future<void> clear(String sessionKey) async {
    final k = sessionKey.trim();
    if (k.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.remove('$_prefix$k');
  }
}
