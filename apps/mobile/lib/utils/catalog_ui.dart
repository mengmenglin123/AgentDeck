import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/app_settings_controller.dart';

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  /// Wire periodic refresh from AppSettingsController.dashboardRefreshSec.
  static Timer? armAutoRefresh({
    required BuildContext context,
    required Timer? current,
    required bool enabled,
    required bool Function() isBusy,
    required VoidCallback onTick,
  }) {
    current?.cancel();
    if (!enabled || !context.mounted) return null;
    final sec = context.read<AppSettingsController>().dashboardRefreshSec;
    if (sec <= 0) return null;
    return Timer.periodic(Duration(seconds: sec), (_) {
      if (!context.mounted || isBusy()) return;
      onTick();
    });
  }

  static void jumpScroll(ScrollController scroll, {required bool top}) {
    if (!scroll.hasClients) return;
    scroll.animateTo(
      top ? 0 : scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Compact AppBar action: copy-all / csv / jump / wrap / auto / refresh.
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
    List<Widget> extra = const [],
  }) {
    return [
      if (onCopyAll != null)
        IconButton(
          tooltip: copyAll,
          onPressed: onCopyAll,
          icon: const Icon(Icons.copy_all_outlined),
        ),
      if (onCopyCsv != null)
        IconButton(
          tooltip: copyCsv,
          onPressed: onCopyCsv,
          icon: const Icon(Icons.table_chart_outlined),
        ),
      IconButton(
        tooltip: wrapLines ? clampDetails : wrapDetails,
        onPressed: onToggleWrap,
        icon: Icon(wrapLines ? Icons.wrap_text : Icons.notes),
      ),
      IconButton(
        tooltip: jumpTop,
        onPressed: () => jumpScroll(scroll, top: true),
        icon: const Icon(Icons.vertical_align_top),
      ),
      IconButton(
        tooltip: jumpBottom,
        onPressed: () => jumpScroll(scroll, top: false),
        icon: const Icon(Icons.vertical_align_bottom),
      ),
      IconButton(
        tooltip: autoRefresh ? pauseRefresh : autoRefreshLabel,
        onPressed: onToggleAuto,
        icon: Icon(
          autoRefresh
              ? Icons.pause_circle_outline
              : Icons.play_circle_outline,
        ),
      ),
      IconButton(
        tooltip: refresh,
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh),
      ),
      ...extra,
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
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: onSel,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        chip(CatalogUi.wrap, wrapLines, onWrap),
        chip(AppStrings.regex, regex, onRegex),
        chip(AppStrings.matchCase, matchCase, onCase),
        chip(CatalogUi.auto, autoRefresh, onAuto),
      ],
    );
  }
}
