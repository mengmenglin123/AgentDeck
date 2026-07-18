import 'package:flutter/foundation.dart';

/// In-memory redacted audit ring for local debugging (P1-7).
class AuditLog extends ChangeNotifier {
  AuditLog({this.capacity = 200});

  final int capacity;
  final List<AuditEntry> _entries = [];

  List<AuditEntry> get entries => List.unmodifiable(_entries);

  void add(String action, {String? detail, String level = 'info'}) {
    final redacted = _redact(detail ?? '');
    _entries.add(
      AuditEntry(
        ts: DateTime.now(),
        action: action,
        detail: redacted,
        level: level,
      ),
    );
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  static String _redact(String s) {
    var out = s;
    out = out.replaceAll(
      RegExp(r'token=[^&\s]+', caseSensitive: false),
      'token=***',
    );
    out = out.replaceAll(
      RegExp(r'Bearer\s+\S+', caseSensitive: false),
      'Bearer ***',
    );
    out = out.replaceAll(
      RegExp(
        r'(bridgeToken|mgmtToken|api_key|apiKey)\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      r'$1=***',
    );
    return out;
  }
}

class AuditEntry {
  AuditEntry({
    required this.ts,
    required this.action,
    required this.detail,
    required this.level,
  });

  final DateTime ts;
  final String action;
  final String detail;
  final String level;
}
