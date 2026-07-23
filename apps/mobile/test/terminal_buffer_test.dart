import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/services/terminal_buffer.dart';

void main() {
  test('bounds output and keeps the newest complete content', () {
    final buffer = TerminalBuffer(maxChars: 24);
    buffer.writeln('old line one');
    buffer.writeln('old line two');
    buffer.writeln('newest line');

    expect(buffer.length, lessThanOrEqualTo(24));
    expect(buffer.toString(), contains('newest line'));
    expect(buffer.toString(), isNot(contains('old line one')));
  });

  test('clear resets the bounded buffer', () {
    final buffer = TerminalBuffer(maxChars: 8);
    buffer.write('0123456789');
    buffer.clear();

    expect(buffer.length, 0);
    expect(buffer.toString(), isEmpty);
  });
}
