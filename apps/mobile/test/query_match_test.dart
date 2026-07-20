import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/utils/query_match.dart';

void main() {
  test('QueryMatch empty query matches all', () {
    expect(QueryMatch.matches('hello', ''), isTrue);
  });

  test('QueryMatch case insensitive', () {
    expect(QueryMatch.matches('Hello World', 'hello'), isTrue);
    expect(QueryMatch.matches('Hello World', 'HELLO', caseSensitive: true), isFalse);
  });

  test('QueryMatch regex', () {
    expect(QueryMatch.matches('abc123', r'\d+', regex: true), isTrue);
    expect(QueryMatch.matches('abc', r'\d+', regex: true), isFalse);
  });

  test('QueryMatch invalid regex fails closed', () {
    expect(QueryMatch.matches('abc', r'[', regex: true), isFalse);
  });
}
