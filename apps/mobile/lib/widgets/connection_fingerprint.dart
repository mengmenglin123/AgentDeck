import 'dart:convert';

import 'package:flutter/material.dart';

/// Deterministic visual fingerprint for a connection string (not a scannable QR).
/// Camera QR pairing remains a future P4 item; this is share/verify UX only.
class ConnectionFingerprint extends StatelessWidget {
  const ConnectionFingerprint({
    super.key,
    required this.seed,
    this.size = 160,
    this.cells = 11,
  });

  final String seed;
  final double size;
  final int cells;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bits = _bits(seed, cells);
    return CustomPaint(
      size: Size.square(size),
      painter: _FingerprintPainter(
        bits: bits,
        cells: cells,
        fg: cs.onSurface,
        bg: cs.surfaceContainerHighest,
        accent: cs.primary,
      ),
    );
  }

  static List<bool> _bits(String seed, int cells) {
    final bytes = utf8.encode(seed);
    var state = 2166136261;
    for (final b in bytes) {
      state = (state ^ b) * 16777619;
      state &= 0xFFFFFFFF;
    }
    final n = cells * cells;
    final out = List<bool>.filled(n, false);
    for (var i = 0; i < n; i++) {
      state = (1103515245 * state + 12345) & 0x7FFFFFFF;
      out[i] = (state & 1) == 1;
    }
    void setCell(int r, int c, bool v) {
      if (r >= 0 && r < cells && c >= 0 && c < cells) {
        out[r * cells + c] = v;
      }
    }

    for (final corner in [(0, 0), (0, cells - 3), (cells - 3, 0)]) {
      final r0 = corner[0];
      final c0 = corner[1];
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 3; c++) {
          final edge = r == 0 || r == 2 || c == 0 || c == 2;
          setCell(r0 + r, c0 + c, edge || (r == 1 && c == 1));
        }
      }
    }
    return out;
  }
}

class _FingerprintPainter extends CustomPainter {
  _FingerprintPainter({
    required this.bits,
    required this.cells,
    required this.fg,
    required this.bg,
    required this.accent,
  });

  final List<bool> bits;
  final int cells;
  final Color fg;
  final Color bg;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / cells;
    final bgPaint = Paint()..color = bg;
    final fgPaint = Paint()..color = fg;
    final accentPaint = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      bgPaint,
    );
    for (var r = 0; r < cells; r++) {
      for (var c = 0; c < cells; c++) {
        final i = r * cells + c;
        if (i >= bits.length || !bits[i]) continue;
        final rect = Rect.fromLTWH(
          c * cell + 1,
          r * cell + 1,
          cell - 2,
          cell - 2,
        );
        final corner =
            (r < 3 && c < 3) ||
            (r < 3 && c >= cells - 3) ||
            (r >= cells - 3 && c < 3);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          corner ? accentPaint : fgPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FingerprintPainter oldDelegate) =>
      oldDelegate.seedBits() != seedBits() || oldDelegate.cells != cells;

  String seedBits() => bits.map((b) => b ? '1' : '0').join();
}
