import 'package:flutter/material.dart';

import '../models/session_info.dart';
import '../services/session_controller.dart';

/// Shared project/agent scope control used by the console shell.
///
/// Every project-owned catalog must use the selected project. Showing the
/// model and channel summary next to the selector makes scope changes visible
/// before the user opens Skills, MCP, Chat, or Terminal.
class AgentScopeSelector extends StatelessWidget {
  const AgentScopeSelector({
    super.key,
    required this.sessions,
    this.compact = false,
  });

  final SessionController sessions;
  final bool compact;

  ProjectInfo? get _selected {
    for (final project in sessions.projects) {
      if (project.name == sessions.selectedProject) return project;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final project = _selected;
    final cs = Theme.of(context).colorScheme;
    final name = project?.name ?? sessions.selectedProject ?? '未选择 Agent';
    final agentType = project?.agentType;
    final models = project?.models ?? const <String>[];
    final channels = project?.channels ?? const <String>[];
    final summary = [
      if (agentType != null && agentType.isNotEmpty) agentType,
      if (models.isNotEmpty) '模型 ${models.join('、')}',
      if (channels.isNotEmpty) '渠道 ${channels.join('、')}',
    ].join(' · ');

    return Row(
      children: [
        Icon(Icons.smart_toy_outlined, size: compact ? 18 : 20,
            color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: sessions.projects.any((item) => item.name == name)
                  ? name
                  : null,
              isExpanded: true,
              isDense: compact,
              hint: Text(name, overflow: TextOverflow.ellipsis),
              onChanged: sessions.projects.isEmpty
                  ? null
                  : sessions.selectProject,
              items: sessions.projects
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.name,
                      child: Text(
                        '${item.name} · ${item.agentType}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              summary,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
