import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lightweight Markdown renderer (no extra packages).
/// Covers headings, lists, fenced code (+lang/copy + token tint), inline code, bold/italic.
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
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 4, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (b.lang == null || b.lang!.isEmpty) ? 'code' : b.lang!,
                            style: const TextStyle(
                              color: Color(0xFF9E9E9E),
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy code',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                          icon: const Icon(Icons.copy, size: 16, color: Color(0xFFBDBDBD)),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: b.text));
                            if (context.mounted) {
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                const SnackBar(
                                  content: Text('Code copied'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: SelectableText.rich(
                      _highlightCode(b.text, b.lang, codeBase.copyWith(
                        color: const Color(0xFFB2FF59),
                        backgroundColor: Colors.transparent,
                      )),
                    ),
                  ),
                ],
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
          else if (b.kind != _BlockKind.blank)
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
    String? lang;
    for (final line in lines) {
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          out.add(_Block(_BlockKind.code, codeBuf.toString().trimRight(), lang: lang));
          codeBuf.clear();
          inCode = false;
          lang = null;
        } else {
          inCode = true;
          final fence = line.trimLeft().substring(3).trim();
          lang = fence.isEmpty ? null : fence.split(RegExp(r'\s+')).first;
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
      out.add(_Block(_BlockKind.code, codeBuf.toString().trimRight(), lang: lang));
    }
    return out;
  }


  /// Lightweight fenced-code token tint (no external highlighter deps).
  /// Colors comments / strings / keywords for common langs; falls back to plain.
  static TextSpan _highlightCode(String text, String? lang, TextStyle base) {
    if (text.isEmpty) return TextSpan(text: text, style: base);
    final kw = _keywordsFor(lang);
    final spans = <TextSpan>[];
    // Avoid nested quote hell: match line comments, block comments, strings, numbers, words.
    final re = RegExp(
      r'(//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*|"[^"\\]*(?:\\.[^"\\]*)*"|'
      r"'[^'\\]*(?:\\.[^'\\]*)*'|"
      r'\b\d+(?:\.\d+)?\b|\b[A-Za-z_][\w]*\b)',
      multiLine: true,
    );
    var i = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > i) {
        spans.add(TextSpan(text: text.substring(i, m.start), style: base));
      }
      final tok = m.group(0)!;
      Color? color;
      final isHashComment = tok.startsWith('#') &&
          !(lang ?? '').toLowerCase().startsWith('dart') &&
          !(lang ?? '').toLowerCase().startsWith('c');
      if (tok.startsWith('//') || tok.startsWith('/*') || isHashComment) {
        color = const Color(0xFF6A9955);
      } else if ((tok.startsWith('"') && tok.endsWith('"')) ||
          (tok.startsWith("'") && tok.endsWith("'"))) {
        color = const Color(0xFFCE9178);
      } else if (RegExp(r'^\d').hasMatch(tok)) {
        color = const Color(0xFFB5CEA8);
      } else if (kw.contains(tok)) {
        color = const Color(0xFF569CD6);
      }
      spans.add(TextSpan(
        text: tok,
        style: color == null ? base : base.copyWith(color: color),
      ));
      i = m.end;
    }
    if (i < text.length) {
      spans.add(TextSpan(text: text.substring(i), style: base));
    }
    return TextSpan(style: base, children: spans);
  }

  static Set<String> _keywordsFor(String? lang) {
    final l = (lang ?? '').toLowerCase().trim();
    const common = {
      'if', 'else', 'for', 'while', 'return', 'class', 'true', 'false', 'null',
      'import', 'from', 'def', 'function', 'const', 'var', 'let', 'new', 'try',
      'catch', 'throw', 'async', 'await', 'switch', 'case', 'break', 'continue',
      'void', 'int', 'string', 'bool', 'final', 'static', 'public', 'private',
      'protected', 'extends', 'implements', 'interface', 'package', 'export',
      'default', 'this', 'super', 'in', 'of', 'as', 'is', 'with', 'yield',
    };
    if (l.isEmpty || l == 'text' || l == 'plain') return common;
    if (l == 'dart' || l == 'flutter') {
      return {
        ...common,
        'widget', 'build', 'override', 'required', 'factory', 'mixin',
        'typedef', 'enum', 'get', 'set', 'late', 'dynamic', 'abstract',
      };
    }
    if (l == 'py' || l == 'python') {
      return {
        ...common,
        'None', 'True', 'False', 'and', 'or', 'not', 'lambda', 'pass',
        'raise', 'except', 'finally', 'elif', 'global', 'nonlocal', 'assert',
        'del',
      };
    }
    if (l == 'js' || l == 'ts' || l == 'javascript' || l == 'typescript') {
      return {
        ...common,
        'typeof', 'instanceof', 'undefined', 'type', 'namespace', 'module',
      };
    }
    if (l == 'go' || l == 'golang') {
      return {
        ...common,
        'func', 'struct', 'map', 'chan', 'go', 'defer', 'range', 'select',
        'make', 'nil',
      };
    }
    if (l == 'rs' || l == 'rust') {
      return {
        ...common,
        'fn', 'mut', 'impl', 'trait', 'mod', 'use', 'pub', 'crate', 'match',
        'loop', 'where', 'move', 'ref', 'dyn',
      };
    }
    if (l == 'sh' || l == 'bash' || l == 'shell' || l == 'zsh') {
      return {
        ...common,
        'then', 'fi', 'do', 'done', 'elif', 'esac', 'local', 'echo', 'cd',
        'pwd', 'exit', 'source',
      };
    }
    if (l == 'json') return {'true', 'false', 'null'};
    return common;
  }

  static TextSpan _inline(String text, TextStyle base) {
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
  const _Block(this.kind, this.text, {this.lang});
  final _BlockKind kind;
  final String text;
  final String? lang;
}
