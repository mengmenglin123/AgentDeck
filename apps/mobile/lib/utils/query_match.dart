/// Shared text / regex query matching used by catalog & session screens.
class QueryMatch {
  QueryMatch._();

  /// Returns true if [haystack] matches [query].
  /// Empty query always matches.
  static bool matches(
    String haystack,
    String query, {
    bool caseSensitive = false,
    bool regex = false,
  }) {
    final raw = query.trim();
    if (raw.isEmpty) return true;
    if (regex) {
      try {
        return RegExp(raw, caseSensitive: caseSensitive).hasMatch(haystack);
      } catch (_) {
        return false;
      }
    }
    if (caseSensitive) return haystack.contains(raw);
    return haystack.toLowerCase().contains(raw.toLowerCase());
  }

  /// Join map-ish fields into a searchable haystack.
  static String haystackOf(Iterable<Object?> parts) {
    final buf = StringBuffer();
    for (final p in parts) {
      if (p == null) continue;
      if (p is List) {
        buf.write(p.join(' '));
      } else {
        buf.write(p);
      }
      buf.write(' ');
    }
    return buf.toString();
  }
}
