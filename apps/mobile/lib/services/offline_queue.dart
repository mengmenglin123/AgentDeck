import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Queues messages when offline and auto-sends when connection is restored.
class OfflineQueue extends ChangeNotifier {
  OfflineQueue({this.maxQueueSize = 50, this.persistPath});

  final int maxQueueSize;
  final String? persistPath;

  final List<_QueuedMessage> _queue = [];
  bool _enabled = true;

  List<_QueuedMessage> get queue => List.unmodifiable(_queue);
  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;
  bool get enabled => _enabled;

  /// Add a message to the offline queue.
  /// Returns true if queued, false if queue is full.
  bool enqueue({
    required String sessionKey,
    required String content,
    Map<String, dynamic>? extra,
  }) {
    if (_queue.length >= maxQueueSize) return false;
    _queue.add(
      _QueuedMessage(
        sessionKey: sessionKey,
        content: content,
        extra: extra,
        queuedAt: DateTime.now(),
      ),
    );
    notifyListeners();
    _persist();
    return true;
  }

  /// Remove a message from the queue (after successful send).
  void dequeue(_QueuedMessage msg) {
    _queue.remove(msg);
    notifyListeners();
    _persist();
  }

  /// Clear all queued messages.
  void clear() {
    _queue.clear();
    notifyListeners();
    _persist();
  }

  /// Enable/disable the queue.
  void setEnabled(bool v) {
    _enabled = v;
    notifyListeners();
  }

  /// Try to flush all queued messages using the provided sender.
  /// Returns the number of messages successfully sent.
  Future<int> flush(Future<bool> Function(_QueuedMessage msg) sender) async {
    if (_queue.isEmpty) return 0;
    int sent = 0;
    final toRemove = <_QueuedMessage>[];
    for (final msg in List.of(_queue)) {
      try {
        final ok = await sender(msg);
        if (ok) {
          toRemove.add(msg);
          sent++;
        }
      } catch (_) {
        break; // Stop on first failure
      }
    }
    for (final msg in toRemove) {
      _queue.remove(msg);
    }
    if (toRemove.isNotEmpty) {
      notifyListeners();
      _persist();
    }
    return sent;
  }

  /// Persist queue to disk.
  Future<void> _persist() async {
    try {
      final path = persistPath ?? await _defaultPath();
      final data = _queue.map((m) => m.toJson()).toList();
      await File(path).writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  /// Load queue from disk.
  Future<void> load() async {
    try {
      final path = persistPath ?? await _defaultPath();
      final file = File(path);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as List;
      _queue.clear();
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          _queue.add(_QueuedMessage.fromJson(item));
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<String> _defaultPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/offline_queue.json';
  }
}

class _QueuedMessage {
  _QueuedMessage({
    required this.sessionKey,
    required this.content,
    this.extra,
    required this.queuedAt,
  });

  final String sessionKey;
  final String content;
  final Map<String, dynamic>? extra;
  final DateTime queuedAt;

  Map<String, dynamic> toJson() => {
    'sessionKey': sessionKey,
    'content': content,
    if (extra != null) 'extra': extra,
    'queuedAt': queuedAt.toIso8601String(),
  };

  factory _QueuedMessage.fromJson(Map<String, dynamic> json) => _QueuedMessage(
    sessionKey: json['sessionKey']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
    extra: json['extra'] as Map<String, dynamic>?,
    queuedAt:
        DateTime.tryParse(json['queuedAt']?.toString() ?? '') ?? DateTime.now(),
  );
}
