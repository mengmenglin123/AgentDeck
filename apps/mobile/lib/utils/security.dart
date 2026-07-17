
/// Redaction and connection safety helpers (P2-6). Never log raw tokens.
class Security {
  static String redactToken(String? token) {
    if (token == null || token.isEmpty) return '';
    if (token.length <= 8) return '***';
    return '${token.substring(0, 4)}…***';
  }

  static String redactText(String input) {
    var s = input;
    s = s.replaceAllMapped(
      RegExp(r'(Bearer\s+)[A-Za-z0-9._\-+/=]{8,}', caseSensitive: false),
      (m) => '${m[1]}***',
    );
    s = s.replaceAllMapped(
      RegExp(r'([?&]token=)[^&\s]+', caseSensitive: false),
      (m) => '${m[1]}***',
    );
    s = s.replaceAllMapped(
      RegExp(r'((?:api[_-]?key|token|secret|password)\s*[:=]\s*)\S+', caseSensitive: false),
      (m) => '${m[1]}***',
    );
    return s;
  }

  static bool isLocalHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '::1' ||
        h == '10.0.2.2' ||
        h.startsWith('192.168.') ||
        h.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(h);
  }

  static bool shouldWarnPlaintext(String host, bool useTls) =>
      !useTls && !isLocalHost(host);
}
