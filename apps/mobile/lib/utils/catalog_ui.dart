import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';

/// Shared catalog / host-directory UI helpers.
class CatalogUi {
  CatalogUi._();

  // ── Chinese labels used across host catalog screens ──
  static const copyAll = '复制全部';
  static const copyCsv = '复制 CSV';
  static const copyJson = '复制 JSON';
  static const jumpTop = AppStrings.jumpTop;
  static const jumpBottom = AppStrings.jumpBottom;
  static const pauseRefresh = AppStrings.pauseRefresh;
  static const autoRefresh = AppStrings.autoRefresh;
  static const clampDetails = AppStrings.clampDetails;
  static const wrapDetails = AppStrings.wrapDetails;
  static const wrap = AppStrings.wrap;
  static const auto = '自动';
  static const all = AppStrings.filterAll;
  static const refresh = AppStrings.refresh;
  static const search = AppStrings.search;
  static const filter = '筛选';
  static const noMatch = AppStrings.noMatch;
  static const noMatchHint = AppStrings.noMatchHint;
  static const loading = AppStrings.loading;
  static const retry = AppStrings.retry;
  static const copied = AppStrings.copied;
  static const error = AppStrings.error;
  static const clear = '清空';
  static const cancel = AppStrings.cancel;
  static const status = '状态';
  static const name = '名称';
  static const source = '来源';
  static const path = '路径';
  static const level = '级别';
  static const type = '类型';
  static const host = '主机';
  static const wrapOn = '换行详情';
  static const wrapOff = '截断详情';

  static String filterHint({
    required bool regex,
    required bool matchCase,
    String plain = '筛选名称 / 描述',
  }) {
    if (regex && matchCase) return '筛选（正则 · 大小写）';
    if (regex) return '筛选（正则）';
    if (matchCase) return '筛选（区分大小写）';
    return plain;
  }

  static String regexChipTooltip({required bool on}) =>
      on ? '正则 · 大小写 开（长按恢复普通筛选）' : '正则 · 大小写 关（长按恢复普通筛选）';

  static String countTitle(String base, int visible, int total) {
    if (total <= 0) return base;
    if (visible == total) return '$base ($visible)';
    return '$base ($visible/$total)';
  }

  static Future<void> copyText(
    BuildContext context,
    String text, {
    String okMessage = copied,
  }) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    snack(context, okMessage);
  }

  static void snack(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 1),
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  static void jumpScroll(ScrollController scroll, {required bool top}) {
    if (!scroll.hasClients) return;
    scroll.animateTo(
      top ? 0 : scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Mobile-friendly AppBar actions: refresh + auto + overflow menu.
  /// Keeps primary controls visible; secondary copy/jump/wrap go to 更多.
  static List<Widget> commonActions({
    required BuildContext context,
    required ScrollController scroll,
    required bool wrapLines,
    required bool autoRefresh,
    required VoidCallback onToggleWrap,
    required VoidCallback onToggleAuto,
    required VoidCallback? onRefresh,
    VoidCallback? onCopyAll,
    VoidCallback? onCopyCsv,
    VoidCallback? onCopyJson,
    List<PopupMenuEntry<String>> extraMenu = const [],
    Map<String, VoidCallback>? extraHandlers,
    List<Widget> leading = const [],
  }) {
    return [
      ...leading,
      IconButton(
        tooltip: autoRefresh ? pauseRefresh : autoRefreshLabel,
        onPressed: onToggleAuto,
        icon: Icon(
          autoRefresh ? Icons.pause_circle_outline : Icons.play_circle_outline,
        ),
      ),
      IconButton(
        tooltip: refresh,
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh),
      ),
      PopupMenuButton<String>(
        tooltip: AppStrings.more,
        onSelected: (v) {
          switch (v) {
            case 'copy_all':
              onCopyAll?.call();
              return;
            case 'copy_csv':
              onCopyCsv?.call();
              return;
            case 'copy_json':
              onCopyJson?.call();
              return;
            case 'wrap':
              onToggleWrap();
              return;
            case 'top':
              jumpScroll(scroll, top: true);
              return;
            case 'bottom':
              jumpScroll(scroll, top: false);
              return;
            default:
              extraHandlers?[v]?.call();
          }
        },
        itemBuilder: (context) => [
          if (onCopyAll != null)
            PopupMenuItem(value: 'copy_all', child: Text(copyAll)),
          if (onCopyCsv != null)
            PopupMenuItem(value: 'copy_csv', child: Text(copyCsv)),
          if (onCopyJson != null)
            PopupMenuItem(value: 'copy_json', child: Text(copyJson)),
          if (onCopyAll != null || onCopyCsv != null || onCopyJson != null)
            const PopupMenuDivider(),
          PopupMenuItem(
            value: 'wrap',
            child: Text(wrapLines ? clampDetails : wrapDetails),
          ),
          PopupMenuItem(value: 'top', child: Text(jumpTop)),
          PopupMenuItem(value: 'bottom', child: Text(jumpBottom)),
          if (extraMenu.isNotEmpty) ...[
            const PopupMenuDivider(),
            ...extraMenu,
          ],
        ],
      ),
    ];
  }

  // avoid name clash with field autoRefresh bool in callers
  static const autoRefreshLabel = AppStrings.autoRefresh;
}

/// Common query option chips for catalog screens.
class CatalogQueryChips extends StatelessWidget {
  const CatalogQueryChips({
    super.key,
    required this.wrapLines,
    required this.regex,
    required this.matchCase,
    required this.autoRefresh,
    required this.onWrap,
    required this.onRegex,
    required this.onCase,
    required this.onAuto,
  });

  final bool wrapLines;
  final bool regex;
  final bool matchCase;
  final bool autoRefresh;
  final ValueChanged<bool> onWrap;
  final ValueChanged<bool> onRegex;
  final ValueChanged<bool> onCase;
  final ValueChanged<bool> onAuto;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, ValueChanged<bool> onSel) {
      return FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: onSel,
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(CatalogUi.wrap, wrapLines, onWrap),
        chip(AppStrings.regex, regex, onRegex),
        chip(AppStrings.matchCase, matchCase, onCase),
        chip(CatalogUi.auto, autoRefresh, onAuto),
      ],
    );
  }
}
