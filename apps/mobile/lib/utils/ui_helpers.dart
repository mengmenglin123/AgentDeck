import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_settings_controller.dart';
import 'package:provider/provider.dart';

/// SnackBar / clipboard / haptics helpers — kill copy-paste across screens.
class UiHelpers {
  UiHelpers._();

  static void snack(
    BuildContext context,
    String message, {
    bool error = false,
    Duration duration = const Duration(seconds: 2),
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
          backgroundColor: error ? Colors.red.shade700 : null,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }

  static Future<void> copyText(
    BuildContext context,
    String text, {
    String okMessage = '已复制',
    bool haptic = true,
  }) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (haptic && context.mounted) {
      try {
        final s = context.read<AppSettingsController>();
        if (s.hapticsEnabled) {
          await HapticFeedback.selectionClick();
        }
      } catch (_) {}
    }
    if (context.mounted) snack(context, okMessage, duration: const Duration(seconds: 1));
  }

  static Future<void> lightHaptic(BuildContext context) async {
    try {
      final s = context.read<AppSettingsController>();
      if (!s.hapticsEnabled) return;
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }
}
