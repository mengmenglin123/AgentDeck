
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

  test('card uses content, then text, then title', () {
    final r = TranscriptReducer();
    r.applyBridgePayload({'type': 'card', 'content': 'from content'});
    r.applyBridgePayload({'type': 'card', 'text': 'from text'});
    r.applyBridgePayload({'type': 'card', 'title': 'from title'});
    expect(r.messages.map((m) => m.content).toList(),
        ['from content', 'from text', 'from title']);
    expect(r.messages.every((m) => m.role == 'permission'), isTrue);
  });

  test('thinking tool and run_done', () {
    final r = TranscriptReducer();
    r.applyBridgePayload({'type': 'thinking', 'content': 'plan'});
    r.applyBridgePayload({'type': 'tool_call', 'name': 'echo', 'input': 'hi'});
    r.applyBridgePayload({'type': 'tool_result', 'name': 'echo', 'output': 'ok'});
    r.applyBridgePayload({'type': 'run_done', 'status': 'completed'});
    expect(r.messages.any((m) => m.role == 'tool'), isTrue);
    expect(r.messages.last.content.contains('completed'), isTrue);
  });

  test('hydrate reloads history', () {
    final r = TranscriptReducer();
    r.hydrate([
      {'role': 'user', 'content': 'hi'},
      {'role': 'assistant', 'content': 'yo'},
    ]);
    expect(r.messages.length, 2);
    expect(r.messages.first.role, 'user');
  });
}
