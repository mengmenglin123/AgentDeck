import 'package:flutter/material.dart';

/// Lightweight Markdown renderer (no extra packages).
/// Covers headings, lists, fenced code, inline code, bold/italic — enough for
/// console chat richness without pulling flutter_markdown (pub may be geo-blocked).
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(
    this.source, {
    super.key,
    this.style,
    this.codeStyle,
  });

  final String source;
  final TextStyle? style;
  final TextStyle? codeStyle;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final codeBase = codeStyle ??
        base.copyWith(
          fontFamily: 'monospace',
          fontSize: (base.fontSize ?? 14) * 0.92,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.55),
        );
    final blocks = _splitBlocks(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in blocks) ...[
          if (b.kind == _BlockKind.code)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                b.text,
                style: codeBase.copyWith(color: const Color(0xFFB2FF59), backgroundColor: Colors.transparent),
              ),
            )
          else if (b.kind == _BlockKind.h1)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: SelectableText.rich(_inline(b.text, base.copyWith(fontSize: 20, fontWeight: FontWeight.w700))),
            )
          else if (b.kind == _BlockKind.h2)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: SelectableText.rich(_inline(b.text, base.copyWith(fontSize: 17, fontWeight: FontWeight.w700))),
            )
          else if (b.kind == _BlockKind.h3)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: SelectableText.rich(_inline(b.text, base.copyWith(fontSize: 15, fontWeight: FontWeight.w600))),
            )
          else if (b.kind == _BlockKind.list)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '• ', style: base),
                    ..._inline(b.text, base).children ?? [TextSpan(text: b.text, style: base)],
                  ],
                ),
              ),
            )
          else if (b.kind == _BlockKind.quote)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3)),
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
              ),
              child: SelectableText.rich(_inline(b.text, base.copyWith(fontStyle: FontStyle.italic))),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText.rich(_inline(b.text, base)),
            ),
        ],
      ],
    );
  }

  static List<_Block> _splitBlocks(String src) {
    final lines = src.replaceAll('\r\n', '\n').split('\n');
    final out = <_Block>[];
    final codeBuf = StringBuffer();
    var inCode = false;
    for (final line in lines) {
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          out.add(_Block(_BlockKind.code, codeBuf.toString().trimRight()));
          codeBuf.clear();
          inCode = false;
        } else {
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        if (codeBuf.isNotEmpty) codeBuf.writeln();
        codeBuf.write(line);
        continue;
      }
      final t = line.trimRight();
      if (t.isEmpty) {
        out.add(const _Block(_BlockKind.blank, ''));
        continue;
      }
      if (t.startsWith('### ')) {
        out.add(_Block(_BlockKind.h3, t.substring(4)));
      } else if (t.startsWith('## ')) {
        out.add(_Block(_BlockKind.h2, t.substring(3)));
      } else if (t.startsWith('# ')) {
        out.add(_Block(_BlockKind.h1, t.substring(2)));
      } else if (t.startsWith('> ')) {
        out.add(_Block(_BlockKind.quote, t.substring(2)));
      } else if (RegExp(r'^[-*+]\s+').hasMatch(t) || RegExp(r'^\d+\.\s+').hasMatch(t)) {
        final body = t.replaceFirst(RegExp(r'^([-*+]|\d+\.)\s+'), '');
        out.add(_Block(_BlockKind.list, body));
      } else {
        out.add(_Block(_BlockKind.para, t));
      }
    }
    if (inCode && codeBuf.isNotEmpty) {
      out.add(_Block(_BlockKind.code, codeBuf.toString().trimRight()));
    }
    return out;
  }

  static TextSpan _inline(String text, TextStyle base) {
    // Order: code, bold, italic, links as label
    final spans = <InlineSpan>[];
    final re = RegExp(
      r'(`[^`]+`|\*\*[^*]+\*\*|__[^_]+__|\*[^*]+\*|_[^_]+_|\[[^\]]+\]\([^)]+\))',
    );
    var i = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > i) {
        spans.add(TextSpan(text: text.substring(i, m.start), style: base));
      }
      final tok = m.group(0)!;
      if (tok.startsWith('`') && tok.endsWith('`')) {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: base.backgroundColor ?? const Color(0x22000000),
          ),
        ));
      } else if ((tok.startsWith('**') && tok.endsWith('**')) || (tok.startsWith('__') && tok.endsWith('__'))) {
        spans.add(TextSpan(
          text: tok.substring(2, tok.length - 2),
          style: base.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if ((tok.startsWith('*') && tok.endsWith('*')) || (tok.startsWith('_') && tok.endsWith('_'))) {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (tok.startsWith('[')) {
        final label = RegExp(r'\[([^\]]+)\]').firstMatch(tok)?.group(1) ?? tok;
        spans.add(TextSpan(
          text: label,
          style: base.copyWith(
            color: Colors.lightBlue,
            decoration: TextDecoration.underline,
          ),
        ));
      } else {
        spans.add(TextSpan(text: tok, style: base));
      }
      i = m.end;
    }
    if (i < text.length) {
      spans.add(TextSpan(text: text.substring(i), style: base));
    }
    return TextSpan(style: base, children: spans);
  }
}

enum _BlockKind { para, h1, h2, h3, list, code, quote, blank }

class _Block {
  const _Block(this.kind, this.text);
  final _BlockKind kind;
  final String text;
}
