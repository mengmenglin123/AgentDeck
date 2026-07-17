import 'package:shared_preferences/shared_preferences.dart';

/// Device-local archived session keys (hidden from default list; never uploaded).
class SessionArchiveStore {
  static const _k = 'huanhermes.session_archive.v1';

  Future<Set<String>> archived() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_k) ?? const []).toSet();
  }

  Future<bool> isArchived(String sessionKey) async {
    final a = await archived();
    return a.contains(sessionKey);
  }

  Future<void> setArchived(String sessionKey, bool value) async {
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_k) ?? const []).toSet();
    if (value) {
      set.add(sessionKey);
    } else {
      set.remove(sessionKey);
    }
    await p.setStringList(_k, set.toList()..sort());
  }

  Future<void> toggle(String sessionKey) async {
    final cur = await isArchived(sessionKey);
    await setArchived(sessionKey, !cur);
  }
}
