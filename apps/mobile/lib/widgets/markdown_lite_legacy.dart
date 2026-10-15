import 'package:flutter/material.dart';

/// Legacy / rare HTML tags for [MarkdownLite].
/// Kept out of the hot path so the core renderer stays scannable.
///
/// Returns `true` when [tok] was handled (and spans were appended).
bool tryHandleLegacyHtml(String tok, TextStyle base, List<InlineSpan> spans) {
  if (tok.toLowerCase().startsWith('<font')) {
    // HTML font — attr-tolerant; optional color=#RRGGBB; else slight opacity
    final bodyM = RegExp(
      r'<font[^>]*>([^<]+)</font>',
      caseSensitive: false,
    ).firstMatch(tok);
    final body = bodyM?.group(1) ?? tok;
    final colorM = RegExp(
      r'color\s*=\s*#([0-9A-Fa-f]{6})',
      caseSensitive: false,
    ).firstMatch(tok);
    Color? fontColor;
    if (colorM != null) {
      final v = int.tryParse(colorM.group(1)!, radix: 16);
      if (v != null) fontColor = Color(0xFF000000 | v);
    }
    spans.add(
      TextSpan(
        text: body,
        style: base.copyWith(
          color: fontColor ?? base.color?.withValues(alpha: 0.88),
        ),
      ),
    );
  } else if (tok.startsWith('<center>') && tok.endsWith('</center>')) {
    // HTML center lite — TextAlign not on TextSpan; letterSpacing 0.2 demo
    final body = tok.substring(8, tok.length - 9);
    spans.add(
      TextSpan(
        text: body,
        style: base.copyWith(
          letterSpacing: 0.2,
          color: base.color?.withValues(alpha: 0.92),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<acronym')) {
    // HTML acronym — abbr peer; title optional; small-caps-ish w600 + letterSpacing
    final titleM = RegExp(
      r'title="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(tok);
    final titleM2 = RegExp(
      r"title='([^']*)'",
      caseSensitive: false,
    ).firstMatch(tok);
    final bodyM = RegExp(
      r'<acronym[^>]*>([^<]+)</acronym>',
      caseSensitive: false,
    ).firstMatch(tok);
    final body = bodyM?.group(1) ?? tok;
    final title = titleM?.group(1) ?? titleM2?.group(1) ?? '';
    spans.add(
      TextSpan(
        text: body,
        style: base.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          color: base.color,
        ),
      ),
    );
    if (title.isNotEmpty) {
      spans.add(
        TextSpan(
          text: ' ($title)',
          style: base.copyWith(
            fontSize: (base.fontSize ?? 14) * 0.8,
            color: base.color?.withValues(alpha: 0.65),
          ),
        ),
      );
    }
  } else if (tok.startsWith('<nobr>') && tok.endsWith('</nobr>')) {
    // HTML nobr lite — no soft-wrap control on TextSpan; letterSpacing 0.1 keep-together demo
    final body = tok.substring(6, tok.length - 7);
    spans.add(
      TextSpan(text: body, style: base.copyWith(letterSpacing: 0.1)),
    );
  } else if (tok.startsWith('<blink>') && tok.endsWith('</blink>')) {
    // HTML blink lite — static opacity demo (no animation)
    final body = tok.substring(7, tok.length - 8);
    spans.add(
      TextSpan(
        text: body,
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<marquee')) {
    // HTML marquee lite — attr-tolerant; italic + letterSpacing scroll-ish demo
    final bodyM = RegExp(
      r'<marquee[^>]*>([^<]+)</marquee>',
      caseSensitive: false,
    ).firstMatch(tok);
    final body = bodyM?.group(1) ?? tok;
    spans.add(
      TextSpan(
        text: body,
        style: base.copyWith(
          fontStyle: FontStyle.italic,
          letterSpacing: 0.6,
        ),
      ),
    );
  } else if (tok.startsWith('<xmp>') && tok.endsWith('</xmp>')) {
    // HTML xmp — legacy pre-like monospace demo (single-line body)
    final body = tok.substring(5, tok.length - 6);
    spans.add(
      TextSpan(
        text: body,
        style: base.copyWith(
          fontFamily: 'monospace',
          fontSize: (base.fontSize ?? 14) * 0.92,
          color: base.color?.withValues(alpha: 0.88),
        ),
      ),
    );
  } else if (tok.startsWith('<listing>') && tok.endsWith('</listing>')) {
    // HTML listing — legacy pre-like monospace demo (single-line body)
    final body = tok.substring(9, tok.length - 10);
    spans.add(
      TextSpan(
        text: body,
        style: base.copyWith(
          fontFamily: 'monospace',
          fontSize: (base.fontSize ?? 14) * 0.92,
          color: base.color?.withValues(alpha: 0.88),
        ),
      ),
    );
  } else if (tok.startsWith('<plaintext>') &&
      tok.endsWith('</plaintext>')) {
    // HTML plaintext — legacy pre-like monospace demo (single-line body)
    final body = tok.substring(11, tok.length - 12);
    spans.add(
      TextSpan(
        text: body,
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.9),
        ),
      ),
    );
  } else if (tok.startsWith('<dir>') && tok.endsWith('</dir>')) {
    // HTML dir — legacy list-like demo
    final body = tok.substring(5, tok.length - 6);
    spans.add(
      TextSpan(
        text: '• $body',
        style: base.copyWith(
          fontSize: (base.fontSize ?? 14) * 0.95,
          color: base.color?.withValues(alpha: 0.9),
        ),
      ),
    );
  } else if (tok.startsWith('<menu>') && tok.endsWith('</menu>')) {
    // HTML menu — legacy list-like demo
    final body = tok.substring(6, tok.length - 7);
    spans.add(
      TextSpan(
        text: '• $body',
        style: base.copyWith(
          fontSize: (base.fontSize ?? 14) * 0.95,
          color: base.color?.withValues(alpha: 0.9),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<basefont')) {
    // HTML basefont lite — void-ish; size=N → fontSize*0.9 demo; else letterSpacing
    final sizeM = RegExp(
      r'size\s*=\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(tok);
    if (sizeM != null) {
      spans.add(
        TextSpan(
          text: '\u200B',
          style: base.copyWith(fontSize: (base.fontSize ?? 14) * 0.9),
        ),
      );
    } else {
      spans.add(
        TextSpan(text: '\u200B', style: base.copyWith(letterSpacing: 0.2)),
      );
    }
  } else if (tok.toLowerCase().startsWith('<isindex')) {
    // HTML isindex lite — void-ish legacy search prompt demo
    spans.add(
      TextSpan(
        text: '[search]',
        style: base.copyWith(
          color: base.color?.withValues(alpha: 0.5),
          letterSpacing: 0.5,
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<spacer')) {
    // HTML spacer lite — void-ish or body; size=N → em-spaces, else two spaces
    final sizeM = RegExp(
      r'size\s*=\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(tok);
    final n = int.tryParse(sizeM?.group(1) ?? '') ?? 2;
    final count = n.clamp(1, 32);
    spans.add(
      TextSpan(text: List.filled(count, '\u2003').join(), style: base),
    );
  } else if (tok.toLowerCase().startsWith('<nextid')) {
    // HTML nextid lite — void-ish legacy id counter demo
    spans.add(
      TextSpan(
        text: '#id',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<keygen')) {
    // HTML keygen lite — void-ish legacy key pair demo
    spans.add(
      TextSpan(
        text: '[key]',
        style: base.copyWith(
          color: base.color?.withValues(alpha: 0.55),
          letterSpacing: 0.5,
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<bgsound')) {
    // HTML bgsound lite — void-ish legacy background sound demo
    spans.add(
      TextSpan(
        text: '[♪]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<multicol')) {
    // HTML multicol lite — closed body letterSpacing demo, or void ZWSP
    final bodyM = RegExp(
      r'<multicol[^>]*>([^<]*)</multicol>',
      caseSensitive: false,
    ).firstMatch(tok);
    if (bodyM != null) {
      spans.add(
        TextSpan(
          text: bodyM.group(1) ?? '',
          style: base.copyWith(letterSpacing: 0.35),
        ),
      );
    } else {
      spans.add(
        TextSpan(text: '\u200B', style: base.copyWith(letterSpacing: 0.35)),
      );
    }
  } else if (tok.toLowerCase().startsWith('<frameset')) {
    // HTML frameset lite — void-ish / closed legacy frames container demo
    spans.add(
      TextSpan(
        text: '[frames]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<frame')) {
    // HTML frame lite — void-ish legacy frameset child demo
    spans.add(
      TextSpan(
        text: '[frame]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<applet')) {
    // HTML applet lite — void-ish / closed legacy applet demo
    spans.add(
      TextSpan(
        text: '[app]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<noembed')) {
    // HTML noembed lite — closed body or void fallback demo
    final bodyNe = RegExp(
      r'<noembed[^>]*>([^<]+)</noembed>',
      caseSensitive: false,
    ).firstMatch(tok);
    if (bodyNe != null) {
      spans.add(
        TextSpan(
          text: bodyNe.group(1) ?? '',
          style: base.copyWith(color: base.color?.withValues(alpha: 0.7)),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: '[noembed]',
          style: base.copyWith(color: base.color?.withValues(alpha: 0.7)),
        ),
      );
    }
  } else if (tok.toLowerCase().startsWith('<noframes')) {
    // HTML noframes lite — closed body opacity demo, or muted fallback
    final bodyNf = RegExp(
      r'<noframes[^>]*>([^<]*)</noframes>',
      caseSensitive: false,
    ).firstMatch(tok);
    if (bodyNf != null) {
      spans.add(
        TextSpan(
          text: bodyNf.group(1) ?? '',
          style: base.copyWith(color: base.color?.withValues(alpha: 0.7)),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: '[noframes]',
          style: base.copyWith(color: base.color?.withValues(alpha: 0.7)),
        ),
      );
    }
  } else if (tok.toLowerCase().startsWith('<embed')) {
    // HTML embed lite — void-ish legacy plugin demo
    spans.add(
      TextSpan(
        text: '[embed]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<object')) {
    // HTML object lite — closed / void-ish legacy object demo
    spans.add(
      TextSpan(
        text: '[obj]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<param')) {
    // HTML param lite — void-ish legacy object param demo
    spans.add(
      TextSpan(
        text: '[param]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<video')) {
    // HTML video lite — closed / void-ish media demo
    spans.add(
      TextSpan(
        text: '[video]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<track')) {
    // HTML track lite — void-ish media track demo
    spans.add(
      TextSpan(
        text: '[track]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<audio')) {
    // HTML audio lite — closed / void-ish media demo
    spans.add(
      TextSpan(
        text: '[audio]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<picture')) {
    // HTML picture lite — closed / void-ish media demo
    spans.add(
      TextSpan(
        text: '[pic]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<canvas')) {
    // HTML canvas lite — closed / void-ish canvas demo
    spans.add(
      TextSpan(
        text: '[canvas]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<svg')) {
    // HTML svg lite — closed / void-ish svg demo
    spans.add(
      TextSpan(
        text: '[svg]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<math')) {
    // HTML math lite — closed / void-ish math demo
    spans.add(
      TextSpan(
        text: '[math]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<area')) {
    // HTML area lite — void-ish image-map area demo
    spans.add(
      TextSpan(
        text: '[area]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<iframe')) {
    // HTML iframe lite — closed / void-ish iframe demo
    spans.add(
      TextSpan(
        text: '[iframe]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<portal')) {
    // HTML portal lite — closed / void-ish portal demo
    spans.add(
      TextSpan(
        text: '[portal]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<dialog')) {
    // HTML dialog lite — closed / void-ish dialog demo
    spans.add(
      TextSpan(
        text: '[dialog]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<template')) {
    // HTML template lite — closed / void-ish template demo
    spans.add(
      TextSpan(
        text: '[tmpl]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<slot')) {
    // HTML slot lite — closed / void-ish slot demo
    spans.add(
      TextSpan(
        text: '[slot]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<meter')) {
    // HTML meter lite — closed / void-ish meter demo
    spans.add(
      TextSpan(
        text: '[meter]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<progress')) {
    // HTML progress lite — closed / void-ish progress demo
    spans.add(
      TextSpan(
        text: '[progress]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<figure')) {
    // HTML figure lite — closed / void-ish figure demo
    spans.add(
      TextSpan(
        text: '[figure]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<figcaption')) {
    // HTML figcaption — muted demo label
    spans.add(
      TextSpan(
        text: '[figcaption]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<map')) {
    // HTML map — monospace muted demo label
    spans.add(
      TextSpan(
        text: '[map]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<main')) {
    // HTML main — monospace muted demo label
    spans.add(
      TextSpan(
        text: '[main]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<aside')) {
    // HTML aside — monospace muted demo label
    spans.add(
      TextSpan(
        text: '[aside]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<nav')) {
    // HTML nav — monospace muted demo label
    spans.add(
      TextSpan(
        text: '[nav]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<section')) {
    // HTML section — monospace muted demo label
    spans.add(
      TextSpan(
        text: '[section]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<article')) {
    // HTML article — monospace muted demo label
    spans.add(
      TextSpan(
        text: '[article]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<header')) {
    // HTML header — monospace muted demo label
    spans.add(
      TextSpan(
        text: '[header]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<footer')) {
    // HTML footer — muted demo label
    spans.add(
      TextSpan(
        text: '[footer]',
        style: base.copyWith(color: base.color?.withValues(alpha: 0.55)),
      ),
    );
  } else if (tok.toLowerCase().startsWith('<hgroup')) {
    // HTML hgroup — monospace muted demo label
    spans.add(
      TextSpan(
        text: '[hgroup]',
        style: base.copyWith(
          fontFamily: 'monospace',
          color: base.color?.withValues(alpha: 0.55),
        ),
      ),
    );
  } else {
    return false;
  }
  return true;
}

/// Regex fragment (without outer group) for legacy HTML tags.
const String kLegacyHtmlInlinePattern =
r'<font[^>]*>[^<]+</font>|<center>[^<]+</center>|<acronym[^>]*>[^<]+</acronym>|<nobr>[^<]+</nobr>|<blink>[^<]+</blink>|<marquee[^>]*>[^<]+</marquee>|<xmp>[^<]+</xmp>|<listing>[^<]+</listing>|<plaintext>[^<]+</plaintext>|<dir>[^<]+</dir>|<menu>[^<]+</menu>|<basefont[^>]*/?>|<isindex[^>]*/?>|<spacer[^>]*>[^<]*</spacer>|<spacer[^>]*/?>|<nextid[^>]*/?>|<keygen[^>]*/?>|<bgsound[^>]*/?>|<multicol[^>]*>[^<]*</multicol>|<multicol[^>]*/?>|<frame[^>]*/?>|<frameset[^>]*>[^<]*</frameset>|<frameset[^>]*/?>|<applet[^>]*>[^<]*</applet>|<applet[^>]*/?>|<noembed[^>]*>[^<]+</noembed>|<noembed[^>]*/?>|<noframes[^>]*>[^<]*</noframes>|<noframes[^>]*/?>|<embed[^>]*/?>|<object[^>]*>[^<]*</object>|<object[^>]*/?>|<param[^>]*/?>|<track[^>]*/?>|<video[^>]*>[^<]*</video>|<video[^>]*/?>|<audio[^>]*>[^<]*</audio>|<audio[^>]*/?>|<picture[^>]*>[^<]*</picture>|<picture[^>]*/?>|<canvas[^>]*>[^<]*</canvas>|<canvas[^>]*/?>|<svg[^>]*>[^<]*</svg>|<svg[^>]*/?>|<math[^>]*>[^<]*</math>|<math[^>]*/?>|<area[^>]*/?>|<iframe[^>]*>[^<]*</iframe>|<iframe[^>]*/?>|<portal[^>]*>[^<]*</portal>|<portal[^>]*/?>|<dialog[^>]*>[^<]*</dialog>|<dialog[^>]*/?>|<template[^>]*>[^<]*</template>|<template[^>]*/?>|<slot[^>]*>[^<]*</slot>|<slot[^>]*/?>|<meter[^>]*>[^<]*</meter>|<meter[^>]*/?>|<progress[^>]*>[^<]*</progress>|<progress[^>]*/?>|<figure[^>]*>[^<]*</figure>|<figure[^>]*/?>|<figcaption[^>]*>[^<]*</figcaption>|<figcaption[^>]*/?>|<map[^>]*>[^<]*</map>|<map[^>]*/?>|<main[^>]*>[^<]*</main>|<main[^>]*/?>|<aside[^>]*>[^<]*</aside>|<aside[^>]*/?>|<nav[^>]*>[^<]*</nav>|<nav[^>]*/?>|<section[^>]*>[^<]*</section>|<section[^>]*/?>|<article[^>]*>[^<]*</article>|<article[^>]*/?>|<header[^>]*>[^<]*</header>|<header[^>]*/?>|<footer[^>]*>[^<]*</footer>|<footer[^>]*/?>|<hgroup[^>]*>[^<]*</hgroup>|<hgroup[^>]*/?>';
