import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lightweight Markdown renderer (no extra packages).
/// Covers headings (h1–h6), lists (bullets+ordered), task lists, multi-line quotes, tables, hr, fenced code, links, images(alt), callouts, details, footnotes, h4/h5/h6, abbr, mark (== / HTML <mark>), spoiler, kbd, sup/sub, underline, del, ins, s, strike, br, small, cite, q, var, samp, dfn, em, strong, b, code, i, big, tt, time, data, bdi, bdo, ruby, rt, rp, wbr, font, center, acronym, nobr, blink, marquee, xmp, listing, plaintext, basefont, dir, menu, isindex, spacer, nextid, keygen, bgsound, multicol, frame, frameset, applet, noembed, noframes, embed, object, param, track, video, autolink, strike (~~ / <s>/<del>/<strike>), inline code, bold/italic, bold-italic (***).
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
                            (() {
                              final lang = (b.lang == null || b.lang!.isEmpty) ? 'code' : b.lang!;
                              final n = b.text.isEmpty ? 0 : b.text.split('\n').length;
                              return '$lang · $n lines';
                            })(),
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
                    padding: const EdgeInsets.fromLTRB(6, 0, 10, 10),
                    child: SelectableText.rich(
                      _withLineNumbers(
                        b.text,
                        b.lang,
                        codeBase.copyWith(
                          color: const Color(0xFFB2FF59),
                          backgroundColor: Colors.transparent,
                          height: 1.35,
                        ),
                      ),
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
          else if (b.kind == _BlockKind.h4)
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 2),
              child: SelectableText.rich(_inline(b.text, base.copyWith(fontSize: 14, fontWeight: FontWeight.w600))),
            )
          else if (b.kind == _BlockKind.h5)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 1),
              child: SelectableText.rich(_inline(b.text, base.copyWith(fontSize: 13, fontWeight: FontWeight.w600))),
            )
          else if (b.kind == _BlockKind.h6)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 1),
              child: SelectableText.rich(_inline(b.text, base.copyWith(fontSize: 12, fontWeight: FontWeight.w600))),
            )
          else if (b.kind == _BlockKind.task)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 2, bottom: 2),
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: (b.checked == true) ? '☑ ' : '☐ ',
                      style: base.copyWith(
                        color: (b.checked == true)
                            ? const Color(0xFF81C784)
                            : base.color?.withOpacity(0.75),
                      ),
                    ),
                    ..._inline(b.text, base).children ?? [TextSpan(text: b.text, style: base)],
                  ],
                ),
              ),
            )
          else if (b.kind == _BlockKind.list)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    TextSpan(text: b.marker ?? '• ', style: base),
                    ..._inline(b.text, base).children ?? [TextSpan(text: b.text, style: base)],
                  ],
                ),
              ),
            )
          else if (b.kind == _BlockKind.callout)
            Builder(builder: (context) {
              final tag = (b.marker ?? 'NOTE').toLowerCase();
              Color edge = Colors.blueGrey;
              if (tag.contains('warn') || tag.contains('caution')) {
                edge = Colors.orange;
              } else if (tag.contains('tip') || tag.contains('success')) {
                edge = Colors.teal;
              } else if (tag.contains('important') || tag.contains('error')) {
                edge = Colors.deepOrange;
              }
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: edge, width: 3)),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                ),
                child: SelectableText.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${(b.marker ?? 'NOTE').toUpperCase()}  ',
                        style: base.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: (base.fontSize ?? 14) * 0.85,
                          color: edge,
                        ),
                      ),
                      ..._inline(b.text, base).children ?? [TextSpan(text: b.text, style: base)],
                    ],
                  ),
                ),
              );
            })
          else if (b.kind == _BlockKind.footnote)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4, bottom: 2),
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '[${b.marker ?? '?'}] ',
                      style: base.copyWith(
                        fontSize: (base.fontSize ?? 14) * 0.85,
                        fontWeight: FontWeight.w700,
                        color: Colors.lightBlue,
                      ),
                    ),
                    ..._inline(b.text, base.copyWith(fontSize: (base.fontSize ?? 14) * 0.9)).children ??
                        [TextSpan(text: b.text, style: base)],
                  ],
                ),
              ),
            )
          else if (b.kind == _BlockKind.details)
            Builder(builder: (context) {
              final raw = b.text;
              var summary = 'Details';
              var body = raw;
              final sm = RegExp(r'<summary[^>]*>([\s\S]*?)</summary>', caseSensitive: false).firstMatch(raw);
              if (sm != null) {
                summary = (sm.group(1) ?? 'Details').replaceAll(RegExp(r'<[^>]+>'), '').trim();
                if (summary.isEmpty) summary = 'Details';
                body = raw.replaceFirst(sm.group(0)!, '');
              }
              body = body
                  .replaceAll(RegExp(r'</?details[^>]*>', caseSensitive: false), '')
                  .trim();
              return Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
                  title: SelectableText.rich(_inline(summary, base.copyWith(fontWeight: FontWeight.w600))),
                  children: [
                    if (body.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText.rich(_inline(body, base)),
                      ),
                  ],
                ),
              );
            })
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
          else if (b.kind == _BlockKind.hr)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity(0.6)),
            )
          else if (b.kind == _BlockKind.table)
            _buildTable(context, b.text, base)
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
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
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
        i++;
        continue;
      }
      if (inCode) {
        if (codeBuf.isNotEmpty) codeBuf.writeln();
        codeBuf.write(line);
        i++;
        continue;
      }
      final t = line.trimRight();
      if (t.isEmpty) {
        out.add(const _Block(_BlockKind.blank, ''));
        i++;
        continue;
      }
      // horizontal rule
      if (RegExp(r'^(\*\s*){3,}$|^(-\s*){3,}$|^(_{3,})$').hasMatch(t.trim())) {
        out.add(const _Block(_BlockKind.hr, ''));
        i++;
        continue;
      }
      // GFM table: header | ... then |---|---|
      if (t.contains('|') && i + 1 < lines.length) {
        final sep = lines[i + 1].trim();
        if (RegExp(r'^\|?[\s:-]+\|[\s|:-]+$').hasMatch(sep) ||
            RegExp(r'^:?-{3,}:?(\s*\|\s*:?-{3,}:?)+$').hasMatch(sep.replaceAll('|', '|').trim())) {
          final buf = StringBuffer()..writeln(t)..writeln(lines[i + 1]);
          i += 2;
          while (i < lines.length) {
            final row = lines[i].trimRight();
            if (!row.contains('|') || row.trim().isEmpty) break;
            buf.writeln(row);
            i++;
          }
          out.add(_Block(_BlockKind.table, buf.toString().trimRight()));
          continue;
        }
      }
      final fnDef = RegExp(r'^\[\^([^\]]+)\]:\s*(.*)$').firstMatch(t.trim());
      if (fnDef != null) {
        out.add(_Block(_BlockKind.footnote, fnDef.group(2) ?? '', marker: fnDef.group(1)));
        i++;
        continue;
      }
      if (t.trim().toLowerCase().startsWith('<details')) {
        // <details><summary>…</summary>body</details> — console ExpansionTile
        final buf = StringBuffer()..writeln(t);
        i++;
        while (i < lines.length) {
          final n = lines[i];
          buf.writeln(n);
          i++;
          if (n.toLowerCase().contains('</details>')) break;
        }
        out.add(_Block(_BlockKind.details, buf.toString()));
        continue;
      } else if (t.startsWith('###### ')) {
        out.add(_Block(_BlockKind.h6, t.substring(7)));
      } else if (t.startsWith('##### ')) {
        out.add(_Block(_BlockKind.h5, t.substring(6)));
      } else if (t.startsWith('#### ')) {
        out.add(_Block(_BlockKind.h4, t.substring(5)));
      } else if (t.startsWith('### ')) {
        out.add(_Block(_BlockKind.h3, t.substring(4)));
      } else if (t.startsWith('## ')) {
        out.add(_Block(_BlockKind.h2, t.substring(3)));
      } else if (t.startsWith('# ')) {
        out.add(_Block(_BlockKind.h1, t.substring(2)));
      } else if (t.startsWith('> ') || t.trim() == '>') {
        final first = t.startsWith('> ') ? t.substring(2) : '';
        final calloutMatch = RegExp(r'^\[!(NOTE|TIP|WARNING|WARN|IMPORTANT|CAUTION|ERROR)\]\s*(.*)$', caseSensitive: false).firstMatch(first.trim());
        final buf = StringBuffer();
        String? calloutTag;
        if (calloutMatch != null) {
          calloutTag = calloutMatch.group(1);
          final rest = (calloutMatch.group(2) ?? '').trim();
          if (rest.isNotEmpty) buf.write(rest);
        } else {
          buf.write(first);
        }
        i++;
        while (i < lines.length) {
          final n = lines[i].trimRight();
          if (n.startsWith('> ')) {
            if (buf.isNotEmpty) buf.writeln();
            buf.write(n.substring(2));
            i++;
          } else if (n.trim() == '>') {
            if (buf.isNotEmpty) buf.writeln();
            i++;
          } else {
            break;
          }
        }
        if (calloutTag != null) {
          out.add(_Block(_BlockKind.callout, buf.toString(), marker: calloutTag));
        } else {
          out.add(_Block(_BlockKind.quote, buf.toString()));
        }
        continue;
      } else if (RegExp(r'^[-*+]\s+\[[ xX]\]\s+').hasMatch(t)) {
        final checked = RegExp(r'^[-*+]\s+\[([xX])\]\s+').hasMatch(t);
        final body = t.replaceFirst(RegExp(r'^[-*+]\s+\[[ xX]\]\s+'), '');
        out.add(_Block(_BlockKind.task, body, checked: checked));
      } else if (RegExp(r'^\d+\.\s+').hasMatch(t)) {
        final m = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(t)!;
        out.add(_Block(_BlockKind.list, m.group(2)!, marker: '${m.group(1)}. '));
      } else if (RegExp(r'^[-*+]\s+').hasMatch(t)) {
        final body = t.replaceFirst(RegExp(r'^[-*+]\s+'), '');
        out.add(_Block(_BlockKind.list, body, marker: '• '));
      } else {
        out.add(_Block(_BlockKind.para, t));
      }
      i++;
    }
    if (inCode && codeBuf.isNotEmpty) {
      out.add(_Block(_BlockKind.code, codeBuf.toString().trimRight(), lang: lang));
    }
    return out;
  }

  static Widget _buildTable(BuildContext context, String raw, TextStyle base) {
    final rows = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    List<String> cells(String line) {
      var s = line.trim();
      if (s.startsWith('|')) s = s.substring(1);
      if (s.endsWith('|')) s = s.substring(0, s.length - 1);
      return s.split('|').map((c) => c.trim()).toList();
    }
    final parsed = <List<String>>[];
    for (var r = 0; r < rows.length; r++) {
      if (r == 1 && RegExp(r'^[\s|:-]+$').hasMatch(rows[r].replaceAll(' ', ''))) {
        continue; // skip separator
      }
      // also skip classic ---|---
      if (r == 1 && RegExp(r'^:?-{3,}:?(\s*\|\s*:?-{3,}:?)+$').hasMatch(rows[r].trim().replaceAll(' ', ''))) {
        continue;
      }
      if (r == 1) {
        final sepOnly = rows[r].replaceAll(RegExp(r'[\s|:-]'), '');
        if (sepOnly.isEmpty) continue;
      }
      parsed.add(cells(rows[r]));
    }
    if (parsed.isEmpty) return const SizedBox.shrink();
    final cols = parsed.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
    final border = Theme.of(context).dividerColor.withOpacity(0.45);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.symmetric(inside: BorderSide(color: border)),
          children: [
            for (var ri = 0; ri < parsed.length; ri++)
              TableRow(
                decoration: ri == 0
                    ? BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.55))
                    : null,
                children: [
                  for (var ci = 0; ci < cols; ci++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: SelectableText.rich(
                        _inline(ci < parsed[ri].length ? parsed[ri][ci] : '', ri == 0 ? base.copyWith(fontWeight: FontWeight.w700) : base),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }



  /// Prefix each code line with a dim gutter number (display-only).
  static TextSpan _withLineNumbers(String text, String? lang, TextStyle base) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    if (lines.isEmpty) return TextSpan(text: text, style: base);
    final width = lines.length.toString().length;
    final gutterStyle = base.copyWith(
      color: const Color(0xFF6E7681),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final out = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final num = (i + 1).toString().padLeft(width);
      out.add(TextSpan(text: '$num  ', style: gutterStyle));
      final hi = _highlightCode(lines[i], lang, base);
      if (hi.children != null && hi.children!.isNotEmpty) {
        out.addAll(hi.children!);
      } else {
        out.add(TextSpan(text: lines[i], style: base));
      }
      if (i < lines.length - 1) {
        out.add(TextSpan(text: '\n', style: base));
      }
    }
    return TextSpan(style: base, children: out);
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
          r'(~~[^~]+~~|==[^=]+==|\|\|[^|]+\|\||<kbd>[^<]+</kbd>|<sup>[^<]+</sup>|<sub>[^<]+</sub>|<u>[^<]+</u>|<mark>[^<]+</mark>|<del>[^<]+</del>|<ins>[^<]+</ins>|<s>[^<]+</s>|<strike>[^<]+</strike>|<br/>|<br>|<wbr/>|<wbr>|<small>[^<]+</small>|<cite>[^<]+</cite>|<q>[^<]+</q>|<var>[^<]+</var>|<samp>[^<]+</samp>|<dfn>[^<]+</dfn>|<em>[^<]+</em>|<strong>[^<]+</strong>|<b>[^<]+</b>|<code>[^<]+</code>|<i>[^<]+</i>|<big>[^<]+</big>|<tt>[^<]+</tt>|<time>[^<]+</time>|<data>[^<]+</data>|<bdi>[^<]+</bdi>|<bdo[^>]*>[^<]+</bdo>|<ruby>[^<]+<rt>[^<]+</rt></ruby>|<ruby>[^<]+</ruby>|<rt>[^<]+</rt>|<rp>[^<]*</rp>|<font[^>]*>[^<]+</font>|<center>[^<]+</center>|<acronym[^>]*>[^<]+</acronym>|<nobr>[^<]+</nobr>|<blink>[^<]+</blink>|<marquee[^>]*>[^<]+</marquee>|<xmp>[^<]+</xmp>|<listing>[^<]+</listing>|<plaintext>[^<]+</plaintext>|<dir>[^<]+</dir>|<menu>[^<]+</menu>|<basefont[^>]*/?>|<isindex[^>]*/?>|<spacer[^>]*>[^<]*</spacer>|<spacer[^>]*/?>|<nextid[^>]*/?>|<keygen[^>]*/?>|<bgsound[^>]*/?>|<multicol[^>]*>[^<]*</multicol>|<multicol[^>]*/?>|<frame[^>]*/?>|<frameset[^>]*>[^<]*</frameset>|<frameset[^>]*/?>|<applet[^>]*>[^<]*</applet>|<applet[^>]*/?>|<noembed[^>]*>[^<]+</noembed>|<noembed[^>]*/?>|<noframes[^>]*>[^<]*</noframes>|<noframes[^>]*/?>|<embed[^>]*/?>|<object[^>]*>[^<]*</object>|<object[^>]*/?>|<param[^>]*/?>|<track[^>]*/?>|<video[^>]*>[^<]*</video>|<video[^>]*/?>|<abbr[^>]*>[^<]+</abbr>|`[^`]+`|\*\*\*[^*]+\*\*\*|\*\*[^*]+\*\*|__[^_]+__|\*[^*]+\*|_[^_]+_|!\[[^\]]*\]\([^)]+\)|\[\^[^\]]+\]|\[[^\]]+\]\([^)]+\)|https?://[^\s<>\)]+)',
            );
    var i = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > i) {
        spans.add(TextSpan(text: text.substring(i, m.start), style: base));
      }
      final tok = m.group(0)!;
      if (tok.startsWith('~~') && tok.endsWith('~~')) {
        spans.add(TextSpan(
          text: tok.substring(2, tok.length - 2),
          style: base.copyWith(
            decoration: TextDecoration.lineThrough,
            color: base.color?.withOpacity(0.65),
          ),
        ));
      } else if (tok.startsWith('==') && tok.endsWith('==')) {
        spans.add(TextSpan(
          text: tok.substring(2, tok.length - 2),
          style: base.copyWith(
            backgroundColor: const Color(0x66FFEB3B),
            color: base.color,
          ),
        ));
      } else if (tok.startsWith('||') && tok.endsWith('||') && tok.length > 4) {
        spans.add(TextSpan(
          text: tok.substring(2, tok.length - 2),
          style: base.copyWith(
            backgroundColor: const Color(0x66000000),
            color: const Color(0x00000000),
          ),
        ));
      } else if (tok.startsWith('<kbd>') && tok.endsWith('</kbd>')) {
        final body = tok.substring(5, tok.length - 6);
        spans.add(TextSpan(
          text: ' $body ',
          style: base.copyWith(
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 14) * 0.9,
            backgroundColor: const Color(0x22000000),
            color: base.color,
          ),
        ));
      } else if (tok.startsWith('<sup>') && tok.endsWith('</sup>')) {
        final body = tok.substring(5, tok.length - 6);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.75,
            height: 1.0,
            color: base.color?.withOpacity(0.9),
          ),
        ));
      } else if (tok.startsWith('<sub>') && tok.endsWith('</sub>')) {
        final body = tok.substring(5, tok.length - 6);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.75,
            height: 1.2,
            color: base.color?.withOpacity(0.85),
          ),
        ));
      } else if (tok.startsWith('<u>') && tok.endsWith('</u>')) {
        final body = tok.substring(3, tok.length - 4);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            decoration: TextDecoration.underline,
            color: base.color,
          ),
        ));
      } else if (tok.startsWith('<mark>') && tok.endsWith('</mark>')) {
        // HTML mark — same highlight as ==text==
        final body = tok.substring(6, tok.length - 7);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            backgroundColor: const Color(0x66FFEB3B),
            color: base.color,
          ),
        ));
      } else if (tok.startsWith('<del>') && tok.endsWith('</del>')) {
        final body = tok.substring(5, tok.length - 6);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            decoration: TextDecoration.lineThrough,
            color: base.color?.withOpacity(0.7),
          ),
        ));
      } else if (tok.startsWith('<ins>') && tok.endsWith('</ins>')) {
        // HTML insert marker
        final body = tok.substring(5, tok.length - 6);
        final prior = base.decoration;
        final deco = prior == null || prior == TextDecoration.none
            ? TextDecoration.underline
            : TextDecoration.combine(<TextDecoration>[prior, TextDecoration.underline]);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            decoration: deco,
            color: base.color?.withOpacity(0.95),
          ),
        ));
      } else if (tok.startsWith('<s>') && tok.endsWith('</s>')) {
        // HTML strike alias of del
        final body = tok.substring(3, tok.length - 4);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            decoration: TextDecoration.lineThrough,
            color: base.color?.withOpacity(0.7),
          ),
        ));
      } else if (tok.startsWith('<strike>') && tok.endsWith('</strike>')) {
        // HTML strike (legacy) alias of del / s
        final body = tok.substring(8, tok.length - 9);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            decoration: TextDecoration.lineThrough,
            color: base.color?.withOpacity(0.7),
          ),
        ));
      } else if (tok == '<br/>' || tok == '<br>') {
        // HTML line break
        spans.add(const TextSpan(text: '\n'));
      } else if (tok == '<wbr/>' || tok == '<wbr>') {
        // HTML word break opportunity — zero-width space
        spans.add(const TextSpan(text: '\u200B'));
      } else if (tok.startsWith('<small>') && tok.endsWith('</small>')) {
        final body = tok.substring(7, tok.length - 8);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.85,
            color: base.color?.withOpacity(0.85),
          ),
        ));
      } else if (tok.startsWith('<cite>') && tok.endsWith('</cite>')) {
        final body = tok.substring(6, tok.length - 7);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontStyle: FontStyle.italic,
            color: base.color?.withOpacity(0.85),
          ),
        ));
      } else if (tok.startsWith('<q>') && tok.endsWith('</q>')) {
        final body = tok.substring(3, tok.length - 4);
        spans.add(TextSpan(
          text: '“$body”',
          style: base.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ));
      } else if (tok.startsWith('<var>') && tok.endsWith('</var>')) {
        // HTML variable / placeholder name
        final body = tok.substring(5, tok.length - 6);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontStyle: FontStyle.italic,
            fontFamily: 'monospace',
            color: base.color?.withOpacity(0.88),
          ),
        ));
      } else if (tok.startsWith('<samp>') && tok.endsWith('</samp>')) {
        // HTML sample output
        final body = tok.substring(6, tok.length - 7);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: base.backgroundColor ?? const Color(0x22000000),
            color: base.color?.withOpacity(0.9),
          ),
        ));
      } else if (tok.startsWith('<dfn>') && tok.endsWith('</dfn>')) {
        // HTML definition term
        final body = tok.substring(5, tok.length - 6);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
          ),
        ));
      } else if (tok.startsWith('<em>') && tok.endsWith('</em>')) {
        // HTML em alias of *italic*
        final body = tok.substring(4, tok.length - 5);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ));
      } else if (tok.startsWith('<strong>') && tok.endsWith('</strong>')) {
        // HTML strong alias of **bold**
        final body = tok.substring(8, tok.length - 9);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (tok.startsWith('<b>') && tok.endsWith('</b>')) {
        // HTML b alias of **bold**
        final body = tok.substring(3, tok.length - 4);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (tok.startsWith('<code>') && tok.endsWith('</code>')) {
        // HTML code alias of `inline code`
        final body = tok.substring(6, tok.length - 7);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: base.backgroundColor ?? const Color(0x22000000),
          ),
        ));
      } else if (tok.startsWith('<i>') && tok.endsWith('</i>')) {
        // HTML i alias of *italic*
        final body = tok.substring(3, tok.length - 4);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ));
      } else if (tok.startsWith('<big>') && tok.endsWith('</big>')) {
        // HTML big — larger text
        final body = tok.substring(5, tok.length - 6);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 1.15,
          ),
        ));
      } else if (tok.startsWith('<tt>') && tok.endsWith('</tt>')) {
        // HTML tt teletype alias of code-ish monospace (no bg required)
        final body = tok.substring(4, tok.length - 5);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontFamily: 'monospace',
          ),
        ));
      } else if (tok.startsWith('<time>') && tok.endsWith('</time>')) {
        // HTML time — semantic datetime display (muted / slightly smaller)
        final body = tok.substring(6, tok.length - 7);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.92,
            color: base.color?.withOpacity(0.75),
          ),
        ));
      } else if (tok.startsWith('<data>') && tok.endsWith('</data>')) {
        // HTML data — machine-readable value (monospace + slight letterSpacing)
        final body = tok.substring(6, tok.length - 7);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontFamily: 'monospace',
            letterSpacing: 0.4,
            color: base.color?.withOpacity(0.9),
          ),
        ));
      } else if (tok.startsWith('<bdi>') && tok.endsWith('</bdi>')) {
        // HTML bdi — bidirectional isolate (demo: italic + slight letterSpacing)
        final body = tok.substring(5, tok.length - 6);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontStyle: FontStyle.italic,
            letterSpacing: 0.3,
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<bdo')) {
        // HTML bdo — bidirectional override (may carry dir=); strip tags, show inner text
        final bodyM = RegExp(r'<bdo[^>]*>([^<]+)</bdo>', caseSensitive: false).firstMatch(tok);
        final body = bodyM?.group(1) ?? tok;
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontFamily: 'monospace',
            color: base.color?.withOpacity(0.82),
          ),
        ));
      } else if (tok.startsWith('<ruby>') && tok.contains('<rt>') && tok.endsWith('</ruby>')) {
        // HTML ruby with annotation: <ruby>BASE<rt>ANNO</rt></ruby>
        final rm = RegExp(r'<ruby>([^<]+)<rt>([^<]+)</rt></ruby>').firstMatch(tok);
        final baseText = rm?.group(1) ?? tok;
        final anno = rm?.group(2) ?? '';
        spans.add(TextSpan(
          text: baseText,
          style: base.copyWith(
            letterSpacing: 0.3,
          ),
        ));
        if (anno.isNotEmpty) {
          spans.add(TextSpan(
            text: anno,
            style: base.copyWith(
              fontSize: (base.fontSize ?? 14) * 0.75,
              color: base.color?.withOpacity(0.7),
              height: 1.0,
            ),
          ));
        }
      } else if (tok.startsWith('<ruby>') && tok.endsWith('</ruby>')) {
        // HTML ruby base-only fallback
        final body = tok.substring(6, tok.length - 7);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            letterSpacing: 0.3,
          ),
        ));
      } else if (tok.startsWith('<rt>') && tok.endsWith('</rt>')) {
        // HTML rt — ruby annotation / smaller muted text
        final body = tok.substring(4, tok.length - 5);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.75,
            color: base.color?.withOpacity(0.7),
            height: 1.0,
          ),
        ));
      } else if (tok.startsWith('<rp>') && tok.endsWith('</rp>')) {
        // HTML rp — ruby parenthesis fallback (often empty-ish); muted smaller
        final body = tok.substring(4, tok.length - 5);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.85,
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<font')) {
        // HTML font — attr-tolerant; optional color=#RRGGBB; else slight opacity
        final bodyM = RegExp(r'<font[^>]*>([^<]+)</font>', caseSensitive: false).firstMatch(tok);
        final body = bodyM?.group(1) ?? tok;
        final colorM = RegExp(r'color\s*=\s*#([0-9A-Fa-f]{6})', caseSensitive: false).firstMatch(tok);
        Color? fontColor;
        if (colorM != null) {
          final v = int.tryParse(colorM.group(1)!, radix: 16);
          if (v != null) fontColor = Color(0xFF000000 | v);
        }
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            color: fontColor ?? base.color?.withOpacity(0.88),
          ),
        ));
      } else if (tok.startsWith('<center>') && tok.endsWith('</center>')) {
        // HTML center lite — TextAlign not on TextSpan; letterSpacing 0.2 demo
        final body = tok.substring(8, tok.length - 9);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            letterSpacing: 0.2,
            color: base.color?.withOpacity(0.92),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<acronym')) {
        // HTML acronym — abbr peer; title optional; small-caps-ish w600 + letterSpacing
        final titleM = RegExp(r'title="([^"]*)"', caseSensitive: false).firstMatch(tok);
        final titleM2 = RegExp(r"title='([^']*)'", caseSensitive: false).firstMatch(tok);
        final bodyM = RegExp(r'<acronym[^>]*>([^<]+)</acronym>', caseSensitive: false).firstMatch(tok);
        final body = bodyM?.group(1) ?? tok;
        final title = titleM?.group(1) ?? titleM2?.group(1) ?? '';
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            color: base.color,
          ),
        ));
        if (title.isNotEmpty) {
          spans.add(TextSpan(
            text: ' ($title)',
            style: base.copyWith(
              fontSize: (base.fontSize ?? 14) * 0.8,
              color: base.color?.withOpacity(0.65),
            ),
          ));
        }
      } else if (tok.startsWith('<nobr>') && tok.endsWith('</nobr>')) {
        // HTML nobr lite — no soft-wrap control on TextSpan; letterSpacing 0.1 keep-together demo
        final body = tok.substring(6, tok.length - 7);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            letterSpacing: 0.1,
          ),
        ));
      } else if (tok.startsWith('<blink>') && tok.endsWith('</blink>')) {
        // HTML blink lite — static opacity demo (no animation)
        final body = tok.substring(7, tok.length - 8);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<marquee')) {
        // HTML marquee lite — attr-tolerant; italic + letterSpacing scroll-ish demo
        final bodyM = RegExp(r'<marquee[^>]*>([^<]+)</marquee>', caseSensitive: false).firstMatch(tok);
        final body = bodyM?.group(1) ?? tok;
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontStyle: FontStyle.italic,
            letterSpacing: 0.6,
          ),
        ));
      } else if (tok.startsWith('<xmp>') && tok.endsWith('</xmp>')) {
        // HTML xmp — legacy pre-like monospace demo (single-line body)
        final body = tok.substring(5, tok.length - 6);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 14) * 0.92,
            color: base.color?.withOpacity(0.88),
          ),
        ));
      } else if (tok.startsWith('<listing>') && tok.endsWith('</listing>')) {
        // HTML listing — legacy pre-like monospace demo (single-line body)
        final body = tok.substring(9, tok.length - 10);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 14) * 0.92,
            color: base.color?.withOpacity(0.88),
          ),
        ));
      } else if (tok.startsWith('<plaintext>') && tok.endsWith('</plaintext>')) {
        // HTML plaintext — legacy pre-like monospace demo (single-line body)
        final body = tok.substring(11, tok.length - 12);
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            fontFamily: 'monospace',
            color: base.color?.withOpacity(0.9),
          ),
        ));
      } else if (tok.startsWith('<dir>') && tok.endsWith('</dir>')) {
        // HTML dir — legacy list-like demo
        final body = tok.substring(5, tok.length - 6);
        spans.add(TextSpan(
          text: '• $body',
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.95,
            color: base.color?.withOpacity(0.9),
          ),
        ));
      } else if (tok.startsWith('<menu>') && tok.endsWith('</menu>')) {
        // HTML menu — legacy list-like demo
        final body = tok.substring(6, tok.length - 7);
        spans.add(TextSpan(
          text: '• $body',
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.95,
            color: base.color?.withOpacity(0.9),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<basefont')) {
        // HTML basefont lite — void-ish; size=N → fontSize*0.9 demo; else letterSpacing
        final sizeM = RegExp(r'size\s*=\s*(\d+)', caseSensitive: false).firstMatch(tok);
        if (sizeM != null) {
          spans.add(TextSpan(
            text: '\u200B',
            style: base.copyWith(
              fontSize: (base.fontSize ?? 14) * 0.9,
            ),
          ));
        } else {
          spans.add(TextSpan(
            text: '\u200B',
            style: base.copyWith(
              letterSpacing: 0.2,
            ),
          ));
        }
      } else if (tok.toLowerCase().startsWith('<isindex')) {
        // HTML isindex lite — void-ish legacy search prompt demo
        spans.add(TextSpan(
          text: '[search]',
          style: base.copyWith(
            color: base.color?.withOpacity(0.5),
            letterSpacing: 0.5,
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<spacer')) {
        // HTML spacer lite — void-ish or body; size=N → em-spaces, else two spaces
        final sizeM = RegExp(r'size\s*=\s*(\d+)', caseSensitive: false).firstMatch(tok);
        final n = int.tryParse(sizeM?.group(1) ?? '') ?? 2;
        final count = n.clamp(1, 32);
        spans.add(TextSpan(
          text: List.filled(count, '\u2003').join(),
          style: base,
        ));
      } else if (tok.toLowerCase().startsWith('<nextid')) {
        // HTML nextid lite — void-ish legacy id counter demo
        spans.add(TextSpan(
          text: '#id',
          style: base.copyWith(
            fontFamily: 'monospace',
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<keygen')) {
        // HTML keygen lite — void-ish legacy key pair demo
        spans.add(TextSpan(
          text: '[key]',
          style: base.copyWith(
            color: base.color?.withOpacity(0.55),
            letterSpacing: 0.5,
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<bgsound')) {
        // HTML bgsound lite — void-ish legacy background sound demo
        spans.add(TextSpan(
          text: '[♪]',
          style: base.copyWith(
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<multicol')) {
        // HTML multicol lite — closed body letterSpacing demo, or void ZWSP
        final bodyM = RegExp(r'<multicol[^>]*>([^<]*)</multicol>', caseSensitive: false).firstMatch(tok);
        if (bodyM != null) {
          spans.add(TextSpan(
            text: bodyM.group(1) ?? '',
            style: base.copyWith(
              letterSpacing: 0.35,
            ),
          ));
        } else {
          spans.add(TextSpan(
            text: '\u200B',
            style: base.copyWith(
              letterSpacing: 0.35,
            ),
          ));
        }
      } else if (tok.toLowerCase().startsWith('<frameset')) {
        // HTML frameset lite — void-ish / closed legacy frames container demo
        spans.add(TextSpan(
          text: '[frames]',
          style: base.copyWith(
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<frame')) {
        // HTML frame lite — void-ish legacy frameset child demo
        spans.add(TextSpan(
          text: '[frame]',
          style: base.copyWith(
            fontFamily: 'monospace',
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<applet')) {
        // HTML applet lite — void-ish / closed legacy applet demo
        spans.add(TextSpan(
          text: '[app]',
          style: base.copyWith(
            fontFamily: 'monospace',
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<noembed')) {
        // HTML noembed lite — closed body or void fallback demo
        final bodyNe = RegExp(r'<noembed[^>]*>([^<]+)</noembed>', caseSensitive: false).firstMatch(tok);
        if (bodyNe != null) {
          spans.add(TextSpan(
            text: bodyNe.group(1) ?? '',
            style: base.copyWith(
              color: base.color?.withOpacity(0.7),
            ),
          ));
        } else {
          spans.add(TextSpan(
            text: '[noembed]',
            style: base.copyWith(
              color: base.color?.withOpacity(0.7),
            ),
          ));
        }
      } else if (tok.toLowerCase().startsWith('<noframes')) {
        // HTML noframes lite — closed body opacity demo, or muted fallback
        final bodyNf = RegExp(r'<noframes[^>]*>([^<]*)</noframes>', caseSensitive: false).firstMatch(tok);
        if (bodyNf != null) {
          spans.add(TextSpan(
            text: bodyNf.group(1) ?? '',
            style: base.copyWith(
              color: base.color?.withOpacity(0.7),
            ),
          ));
        } else {
          spans.add(TextSpan(
            text: '[noframes]',
            style: base.copyWith(
              color: base.color?.withOpacity(0.7),
            ),
          ));
        }
      } else if (tok.toLowerCase().startsWith('<embed')) {
        // HTML embed lite — void-ish legacy plugin demo
        spans.add(TextSpan(
          text: '[embed]',
          style: base.copyWith(
            fontFamily: 'monospace',
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<object')) {
        // HTML object lite — closed / void-ish legacy object demo
        spans.add(TextSpan(
          text: '[obj]',
          style: base.copyWith(
            fontFamily: 'monospace',
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<param')) {
        // HTML param lite — void-ish legacy object param demo
        spans.add(TextSpan(
          text: '[param]',
          style: base.copyWith(
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<video')) {
        // HTML video lite — closed / void-ish media demo
        spans.add(TextSpan(
          text: '[video]',
          style: base.copyWith(
            fontFamily: 'monospace',
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<track')) {
        // HTML track lite — void-ish media track demo
        spans.add(TextSpan(
          text: '[track]',
          style: base.copyWith(
            color: base.color?.withOpacity(0.55),
          ),
        ));
      } else if (tok.toLowerCase().startsWith('<abbr')) {
        final titleM = RegExp(r'title="([^"]*)"', caseSensitive: false).firstMatch(tok);
        final titleM2 = RegExp(r"title='([^']*)'", caseSensitive: false).firstMatch(tok);
        final bodyM = RegExp(r'<abbr[^>]*>([^<]+)</abbr>', caseSensitive: false).firstMatch(tok);
        final body = bodyM?.group(1) ?? tok;
        final title = titleM?.group(1) ?? titleM2?.group(1) ?? '';
        spans.add(TextSpan(
          text: body,
          style: base.copyWith(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            color: base.color,
          ),
        ));
        if (title.isNotEmpty) {
          spans.add(TextSpan(
            text: ' ($title)',
            style: base.copyWith(
              fontSize: (base.fontSize ?? 14) * 0.8,
              color: base.color?.withOpacity(0.65),
            ),
          ));
        }
      } else if (tok.startsWith('`') && tok.endsWith('`')) {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: base.backgroundColor ?? const Color(0x22000000),
          ),
        ));
      } else if (tok.startsWith('***') && tok.endsWith('***') && tok.length > 6) {
        // bold-italic — must be checked before **
        spans.add(TextSpan(
          text: tok.substring(3, tok.length - 3),
          style: base.copyWith(
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
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
      } else if (tok.startsWith('![')) {
        final im = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)').firstMatch(tok);
        final rawAlt = im?.group(1) ?? '';
        final alt = rawAlt.isEmpty ? 'image' : rawAlt;
        final url = im?.group(2) ?? '';
        // Console-safe: no network fetch / no file_picker; show alt + path only.
        spans.add(TextSpan(
          text: '🖼 $alt',
          style: base.copyWith(
            color: Colors.tealAccent.shade200,
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 14) * 0.95,
          ),
        ));
        if (url.isNotEmpty) {
          spans.add(TextSpan(
            text: ' ($url)',
            style: base.copyWith(
              color: base.color?.withOpacity(0.55),
              fontSize: (base.fontSize ?? 14) * 0.85,
              fontFamily: 'monospace',
            ),
          ));
        }
      } else if (tok.startsWith('[^') && tok.endsWith(']')) {
        final label = tok.substring(2, tok.length - 1);
        spans.add(TextSpan(
          text: '[$label]',
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.75,
            color: Colors.lightBlue,
            fontWeight: FontWeight.w700,
          ),
        ));
      } else if (tok.startsWith('[')) {
        final lm = RegExp(r'\[([^\]]+)\]\(([^)]+)\)').firstMatch(tok);
        final label = lm?.group(1) ?? tok;
        final url = lm?.group(2) ?? '';
        spans.add(TextSpan(
          text: label,
          style: base.copyWith(
            color: Colors.lightBlue,
            decoration: TextDecoration.underline,
          ),
        ));
        if (url.isNotEmpty) {
          spans.add(TextSpan(
            text: ' ↗',
            style: base.copyWith(color: Colors.lightBlue.withOpacity(0.7), fontSize: (base.fontSize ?? 14) * 0.85),
          ));
          // Keep URL as copyable plain trailing text (console-safe; no url_launcher dep).
          spans.add(TextSpan(
            text: ' ($url)',
            style: base.copyWith(
              color: base.color?.withOpacity(0.55),
              fontSize: (base.fontSize ?? 14) * 0.85,
              fontFamily: 'monospace',
            ),
          ));
        }
      } else if (tok.startsWith('http://') || tok.startsWith('https://')) {
        // Bare URL autolink — console-safe (no url_launcher); show + keep copyable.
        var url = tok;
        while (url.isNotEmpty && '.,;:!?'.contains(url[url.length - 1])) {
          url = url.substring(0, url.length - 1);
        }
        spans.add(TextSpan(
          text: url,
          style: base.copyWith(
            color: Colors.lightBlue,
            decoration: TextDecoration.underline,
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 14) * 0.95,
          ),
        ));
        if (url.length < tok.length) {
          spans.add(TextSpan(text: tok.substring(url.length), style: base));
        }
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

enum _BlockKind { para, h1, h2, h3, h4, h5, h6, list, task, code, quote, callout, blank, hr, table, details, footnote }

class _Block {
  const _Block(this.kind, this.text, {this.lang, this.checked, this.marker});
  final _BlockKind kind;
  final String text;
  final String? lang;
  final bool? checked;
  /// Bullet "• " or ordered "1. " etc.
  final String? marker;
}
