import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/widgets/markdown_lite.dart';

void main() {
  test('code token pattern compiles and tokenises', () {
    final toks = MarkdownLite.codeTokenPattern
        .allMatches('final x = "hi"; // note 42')
        .map((m) => m.group(0))
        .toList();
    expect(toks, containsAll(['final', 'x', '"hi"', '// note 42']));
  });

  testWidgets('fenced code block renders without throwing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarkdownLite(
            '# 标题\n\n```dart\nvoid main() {\n  // hi\n  print("x");\n}\n```\n',
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('main', findRichText: true), findsWidgets);
  });

  testWidgets('rich markdown sample renders every block/inline kind', (tester) async {
    const sample = '''
# H1
## H2 **bold** *it* ~~del~~ ==mark== `code` ||spoiler||
Paragraph with [link](https://example.com) and https://example.com/x and footnote[^1].
- item one
- [ ] task
- [x] done
1. first
2. second
> quote <kbd>Ctrl</kbd> <sup>2</sup> <sub>i</sub> <u>u</u> <br> <abbr title="x">AB</abbr>
| a | b |
|---|---|
| 1 | 2 |

---
![img](https://example.com/i.png)
```
plain fence
```
```python
# comment
def f(x): return 'q'
```
''';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: MarkdownLite(sample))),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Paragraph', findRichText: true), findsWidgets);
  });
}
