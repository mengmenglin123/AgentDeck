/// Bounded local terminal output buffer.
///
/// A remote PTY can stay open for hours. Keeping the entire transcript in a
/// StringBuffer would let host output grow the mobile process without bound.
class TerminalBuffer {
  TerminalBuffer({this.maxChars = 200000}) : assert(maxChars > 0);

  final int maxChars;
  String _value = '';

  int get length => _value.length;

  void write(String value) {
    if (value.isEmpty) return;
    _value += value;
    _trim();
  }

  void writeln([String value = '']) {
    write('$value\n');
  }

  void clear() {
    _value = '';
  }

  @override
  String toString() => _value;

  void _trim() {
    if (_value.length <= maxChars) return;
    final keepFrom = _value.length - maxChars;
    final lineStart = _value.indexOf('\n', keepFrom);
    final start = lineStart < 0 ? keepFrom : lineStart + 1;
    final suffix = _value.substring(start);
    const marker = '[较早输出已截断]\n';
    _value = '$marker$suffix';
    if (_value.length > maxChars) {
      _value = _value.substring(_value.length - maxChars);
    }
  }
}
