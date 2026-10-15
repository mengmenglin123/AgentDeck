import 'package:flutter/material.dart';

/// Keeps an AppBar's trailing actions within a phone-width toolbar.
///
/// Several console screens carry 6–10 icon actions; on a ~390dp phone that
/// overflowed the toolbar (the right-most buttons were clipped and the title
/// squeezed to nothing). The first [maxVisible] tooltip'd [IconButton]s stay
/// in the bar; the rest move into a "更多操作" menu that shows each tooltip as
/// its label and keeps disabled actions disabled. Other widgets (an existing
/// popup menu, a progress indicator) are kept in place.
List<Widget> compactAppBarActions(
  List<Widget> actions, {
  int maxVisible = 3,
}) {
  final icons = <IconButton>[];
  final others = <Widget>[];
  for (final a in actions) {
    if (a is IconButton && (a.tooltip?.isNotEmpty ?? false)) {
      icons.add(a);
    } else {
      others.add(a);
    }
  }
  final budget = (maxVisible - others.length).clamp(1, maxVisible);
  if (icons.length <= budget + 1) return actions;

  final visible = icons.take(budget).toList();
  final overflow = icons.skip(budget).toList();
  return [
    ...visible,
    PopupMenuButton<int>(
      tooltip: '更多操作',
      icon: const Icon(Icons.more_horiz),
      onSelected: (i) => overflow[i].onPressed?.call(),
      itemBuilder: (context) => [
        for (var i = 0; i < overflow.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: overflow[i].onPressed != null,
            child: Row(
              children: [
                IconTheme.merge(
                  data: const IconThemeData(size: 20),
                  child: overflow[i].icon,
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(overflow[i].tooltip!)),
              ],
            ),
          ),
      ],
    ),
    ...others,
  ];
}
