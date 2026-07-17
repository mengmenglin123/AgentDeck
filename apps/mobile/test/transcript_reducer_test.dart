import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/models/transcript.dart';

void main() {
  test('stream then done collapses to one assistant message', () {
    final r = TranscriptReducer();
    r.applyBridgePayload({
      'type': 'reply_stream',
      'delta': 'Hel',
      'full_text': 'Hel',
      'done': false,
    });
    r.applyBridgePayload({
      'type': 'reply_stream',
      'delta': 'lo',
      'full_text': 'Hello',
      'done': true,
    });
    expect(r.messages.length, 1);
    expect(r.messages.first.content, 'Hello');
    expect(r.messages.first.streaming, isFalse);
  });

  test('final reply after stream does not duplicate same text', () {
    final r = TranscriptReducer();
    r.applyBridgePayload({
      'type': 'reply_stream',
      'delta': 'Hi',
      'full_text': 'Hi',
      'done': true,
    });
    r.applyBridgePayload({'type': 'reply', 'content': 'Hi'});
    expect(r.messages.length, 1);
    expect(r.messages.first.content, 'Hi');
  });

  test('permission buttons event', () {
    final r = TranscriptReducer();
    r.applyBridgePayload({
      'type': 'buttons',
      'content': 'Allow bash?',
      'buttons': [
        [
          {'text': 'allow', 'data': 'perm:1:allow'}
        ]
      ],
    });
    expect(r.messages.first.role, 'permission');
    expect(r.messages.first.meta['buttons'], isNotEmpty);
  });
}
