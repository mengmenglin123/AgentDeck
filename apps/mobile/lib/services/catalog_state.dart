import 'dart:async';

import 'package:flutter/foundation.dart';

typedef CatalogLoader<T> = Future<T> Function();
typedef CatalogErrorMapper = String Function(Object error);

class CatalogState<T> extends ChangeNotifier {
  CatalogState({
    required CatalogLoader<T> loader,
    CatalogErrorMapper? errorMapper,
    this.refreshInterval = const Duration(seconds: 30),
  })  : _loader = loader,
        _errorMapper = errorMapper ?? ((error) => error.toString());

  CatalogLoader<T> _loader;
  final CatalogErrorMapper _errorMapper;
  final Duration refreshInterval;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  T? value;
  bool loading = false;
  String? error;
  bool autoRefresh = false;

  Future<void> refresh() async {
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final next = await _loader();
      if (_disposed || generation != _generation) return;
      value = next;
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      error = _errorMapper(exception);
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void updateLoader(CatalogLoader<T> loader, {bool refresh = true}) {
    _loader = loader;
    _generation++;
    if (refresh) unawaited(this.refresh());
  }

  void setAutoRefresh(bool enabled) {
    if (autoRefresh == enabled && (enabled ? _timer != null : _timer == null)) {
      return;
    }
    autoRefresh = enabled;
    _timer?.cancel();
    _timer = enabled
        ? Timer.periodic(refreshInterval, (_) {
            if (!loading) unawaited(refresh());
          })
        : null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
