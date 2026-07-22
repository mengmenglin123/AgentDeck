import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import '../utils/catalog_ui.dart';
import '../utils/query_match.dart';
import 'diff_screen.dart';
import '../widgets/markdown_lite.dart';
import '../l10n/app_strings.dart';

/// Readonly Host workspace browser (`GET /workspace`, `/workspace/git`).
/// Console-only — no write/delete; Host is source of truth.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.config});

  final ConnectionConfig config;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late final MgmtClient _client;
  String _path = '';
  Map<String, dynamic>? _node;
  Map<String, dynamic>? _git;
  String? _error;
  bool _loading = true;
  final _filterCtrl = TextEditingController();
  String _filter = '';
  bool _queryCase = false;
  bool _queryRegex = false;

  /// name ascending when true; dirs always first
  bool _wrapLines = false;
  bool _sortAsc = true;
  bool _sortBySize = false;
  bool _sortByMtime = false;
  bool _sortByPath = false;
  bool _sortByType = false;
  bool _sortByName = false;
  bool _sortByDirty = false;
  bool _sortByBranch = false;
  bool _sortByStatus = false;
  bool _sortByChildren = false;

  /// all | dir | file
  String _typeFilter = 'all';
  bool _hideEmpty = false;

  /// empty=all; md|dart|py|json|other
  String _extFilter = '';
  final _scroll = ScrollController();
  Timer? _timer;
  bool _autoRefresh = false;

  @override
  void initState() {
    super.initState();
    _client = MgmtClient(config: widget.config);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _armTimer());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  List<Map> get _visibleEntries {
    final node = _node;
    final raw = (node?['entries'] as List?) ?? const [];
    final rawQ = _filter.trim();
    final q = _queryCase ? rawQ : rawQ.toLowerCase();
    final list = <Map>[];
    for (final e in raw.whereType<Map>()) {
      final type = (e['type'] ?? '').toString().toLowerCase();
      if (_typeFilter == 'dir' && type != 'dir') continue;
      if (_typeFilter == 'file' && type == 'dir') continue;
      if (_hideEmpty && type == 'dir') {
        final children =
            e['children'] ?? e['entries'] ?? e['count'] ?? e['size'];
        if (children is List && children.isEmpty) continue;
        if (children is num && children == 0) continue;
        if (children == null) {
          final emptyFlag = e['empty'];
          if (emptyFlag == true) continue;
        }
      }
      // Extension filter applies to files only; dirs always pass.
      if (_extFilter.isNotEmpty && type != 'dir') {
        final name = (e['name'] ?? '').toString().toLowerCase();
        if (_extFilter == 'other') {
          if (name.endsWith('.md') ||
              name.endsWith('.dart') ||
              name.endsWith('.py') ||
              name.endsWith('.json') ||
              name.endsWith('.yaml') ||
              name.endsWith('.yml') ||
              name.endsWith('.txt') ||
              name.endsWith('.sh')) {
            continue;
          }
        } else {
          final needle = _extFilter.startsWith('.')
              ? _extFilter.toLowerCase()
              : '.${_extFilter.toLowerCase()}';
          if (!name.endsWith(needle)) continue;
        }
      }
      if (rawQ.isNotEmpty) {
        final nameRaw = (e['name'] ?? '').toString();
        final typeRaw = (e['type'] ?? '').toString();
        final hayRaw = '$nameRaw $typeRaw';
        if (_queryRegex) {
          try {
            if (!RegExp(rawQ, caseSensitive: _queryCase).hasMatch(hayRaw))
              continue;
          } catch (_) {
            continue;
          }
        } else {
          final name = _queryCase ? nameRaw : nameRaw.toLowerCase();
          final typeHay = _queryCase ? typeRaw : typeRaw.toLowerCase();
          if (!name.contains(q) && !typeHay.contains(q)) continue;
        }
      }
      list.add(e);
    }
    int rank(Map e) => e['type'] == 'dir' ? 0 : 1;
    list.sort((a, b) {
      final rd = rank(a).compareTo(rank(b));
      if (rd != 0) return rd;
      int mtimeOf(Map e) {
        final v =
            e['mtime'] ?? e['modified'] ?? e['updated'] ?? e['updated_at'];
        if (v is num) {
          final n = v.toDouble();
          return n > 1e12 ? n.round() : (n * 1000).round();
        }
        final p = DateTime.tryParse(v?.toString() ?? '');
        return p?.millisecondsSinceEpoch ?? 0;
      }

      if (_sortByChildren) {
        int childOf(Map x) {
          final v = x['children'] ?? x['entries'] ?? x['count'];
          if (v is List) return v.length;
          if (v is num) return v.round();
          return int.tryParse(v?.toString() ?? '') ?? -1;
        }

        final c = childOf(a).compareTo(childOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByStatus) {
        final sa = (a['status'] ?? a['code'] ?? '').toString().toLowerCase();
        final sb = (b['status'] ?? b['code'] ?? '').toString().toLowerCase();
        final c = sa.compareTo(sb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByBranch) {
        final ba = (a['branch'] ?? '').toString().toLowerCase();
        final bb = (b['branch'] ?? '').toString().toLowerCase();
        final c = ba.compareTo(bb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByDirty) {
        int dirtyOf(Map x) {
          final v = x['dirty'] ?? x['is_dirty'];
          if (v is bool) return v ? 1 : 0;
          final s = (v ?? '').toString().toLowerCase();
          if (s == 'true' || s == '1' || s == 'yes' || s == 'dirty') return 1;
          if (s == 'false' || s == '0' || s == 'no' || s == 'clean') return 0;
          return -1;
        }

        final c = dirtyOf(a).compareTo(dirtyOf(b));
        if (c != 0) return _sortAsc ? -c : c; // asc => dirty first
      } else if (_sortByName) {
        final na = (a['name'] ?? a['path'] ?? '').toString().toLowerCase();
        final nb = (b['name'] ?? b['path'] ?? '').toString().toLowerCase();
        final c = na.compareTo(nb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByType) {
        final ta = (a['type'] ?? a['kind'] ?? a['mime'] ?? a['extension'] ?? '')
            .toString()
            .toLowerCase();
        final tb = (b['type'] ?? b['kind'] ?? b['mime'] ?? b['extension'] ?? '')
            .toString()
            .toLowerCase();
        final c = ta.compareTo(tb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByPath) {
        final pa = (a['path'] ?? a['full_path'] ?? a['name'] ?? '')
            .toString()
            .toLowerCase();
        final pb = (b['path'] ?? b['full_path'] ?? b['name'] ?? '')
            .toString()
            .toLowerCase();
        final c = pa.compareTo(pb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByMtime) {
        final c = mtimeOf(a).compareTo(mtimeOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortBySize) {
        final sa = (a['size'] is num) ? (a['size'] as num).toInt() : -1;
        final sb = (b['size'] is num) ? (b['size'] as num).toInt() : -1;
        final c = sa.compareTo(sb);
        if (c != 0) return _sortAsc ? c : -c;
      }
      final na = (a['name'] ?? '').toString().toLowerCase();
      final nb = (b['name'] ?? '').toString().toLowerCase();
      final c = na.compareTo(nb);
      return _sortAsc ? c : -c;
    });
    return list;
  }

  List<Widget> _breadcrumbChips() {
    final parts = _path.split('/').where((e) => e.isNotEmpty).toList();
    final chips = <Widget>[
      ActionChip(
        label: const Text('/'),
        visualDensity: VisualDensity.compact,
        onPressed: _path.isEmpty ? null : () => _load(path: ''),
      ),
    ];
    var acc = '';
    for (var i = 0; i < parts.length; i++) {
      acc = acc.isEmpty ? parts[i] : (acc + '/' + parts[i]);
      final target = acc;
      final last = i == parts.length - 1;
      chips.add(
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.chevron_right, size: 16),
        ),
      );
      chips.add(
        ActionChip(
          label: Text(parts[i]),
          visualDensity: VisualDensity.compact,
          onPressed: last ? null : () => _load(path: target),
        ),
      );
    }
    return chips;
  }

  Future<void> _load({String? path}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (path != null) {
        _path = path;
        _filter = '';
        _filterCtrl.clear();
      }
    });
    try {
      final node = await _client.workspace(path: _path);
      final git = await _client.workspaceGit();
      if (!mounted) return;
      setState(() {
        _node = node;
        _git = git;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
      });
    }
  }

  void _openEntry(Map entry) {
    final name = entry['name']?.toString() ?? '';
    if (name.isEmpty) return;
    final next = _path.isEmpty ? name : '$_path/$name';
    _load(path: next);
  }

  String? _codeLangFor(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    const map = {
      'py': 'python',
      'js': 'javascript',
      'ts': 'typescript',
      'dart': 'dart',
      'java': 'java',
      'kt': 'kotlin',
      'swift': 'swift',
      'rb': 'ruby',
      'go': 'go',
      'rs': 'rust',
      'c': 'c',
      'cpp': 'cpp',
      'h': 'c',
      'sh': 'bash',
      'bash': 'bash',
      'zsh': 'zsh',
      'yml': 'yaml',
      'yaml': 'yaml',
      'json': 'json',
      'xml': 'xml',
      'html': 'html',
      'css': 'css',
      'sql': 'sql',
      'md': 'markdown',
      'toml': 'toml',
      'ini': 'ini',
      'cfg': 'ini',
      'conf': 'nginx',
      'dockerfile': 'dockerfile',
    };
    return map[ext];
  }

  void _openDiff([String? path]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiffScreen(config: widget.config, initialPath: path),
      ),
    );
  }

  Future<void> _gitCommit() async {
    final msgCtrl = TextEditingController();
    final msg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.gitCommitTitle),
        content: TextField(
          controller: msgCtrl,
          decoration: const InputDecoration(
            hintText: '提交说明',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, msgCtrl.text.trim()),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (msg == null || msg.isEmpty) return;
    try {
      final result = await _client.gitCommit(message: msg);
      if (!mounted) return;
      final sha = result['data']?['sha'] ?? '?';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已提交：$sha'),
          duration: const Duration(seconds: 2),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('提交失败：$e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _gitPush() async {
    try {
      final result = await _client.gitPush();
      if (!mounted) return;
      final output = result['data']?['output'] ?? 'Pushed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已推送：$output'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('推送失败：$e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _gitPull() async {
    try {
      final result = await _client.gitPull();
      if (!mounted) return;
      final output = result['data']?['output'] ?? 'Pulled';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已拉取：$output'),
          duration: const Duration(seconds: 2),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('拉取失败：$e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _armTimer() {
    _timer = CatalogUi.armAutoRefresh(
      context: context,
      current: _timer,
      enabled: _autoRefresh,
      isBusy: () => _loading,
      onTick: _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final node = _node;
    final isFile = node?['type'] == 'file';
    final entries = (node?['entries'] as List?) ?? const [];
    final parent = node?['parent']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isFile
              ? '工作区'
              : (() {
                  final vis = _visibleEntries;
                  if (entries.isEmpty) return 'Workspace';
                  if (vis.length == entries.length) {
                    return '工作区 (${vis.length})';
                  }
                  return '工作区 (${vis.length}/${entries.length})';
                })(),
        ),
        actions: [
          IconButton(
            tooltip: '复制路径',
            onPressed: () async {
              final p = _path.isEmpty ? '/' : '/$_path';
              await Clipboard.setData(ClipboardData(text: p));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已复制 $p'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: '复制列表',
            onPressed: () async {
              final list = <String>[];
              final p = _path.isEmpty ? '/' : '/$_path';
              list.add(p);
              for (final e in _visibleEntries) {
                final name = e['name']?.toString() ?? '';
                final typ = e['type']?.toString() ?? '';
                if (name.isEmpty) continue;
                list.add(
                  (typ == 'dir' || typ == 'directory' ? 'd ' : 'f ') + name,
                );
              }
              if (list.length <= 1 && !isFile) {
                list.add('(empty)');
              }
              if (isFile) {
                list.add('file: ' + (_node?['name']?.toString() ?? _path));
              }
              await Clipboard.setData(ClipboardData(text: list.join('\n')));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '已复制列表（' + (list.length - 1).toString() + ')',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            icon: const Icon(Icons.playlist_add_check_outlined),
          ),
          IconButton(
            tooltip: '复制列表 CSV',
            onPressed: () async {
              final buf = StringBuffer();
              buf.writeln('name,type,size,path');
              final base = _path.isEmpty ? '' : _path;
              for (final e in _visibleEntries) {
                final name = (e['name'] ?? '').toString().replaceAll('"', '""');
                final typ = (e['type'] ?? '').toString().replaceAll('"', '""');
                final size = e['size'] ?? '';
                final rel = base.isEmpty ? name : '$base/$name';
                final path = rel.replaceAll('"', '""');
                if (name.isEmpty) continue;
                buf.writeln('"$name","$typ",$size,"$path"');
              }
              await Clipboard.setData(ClipboardData(text: buf.toString()));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Copied listing CSV (${_visibleEntries.length})',
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: '回到顶部',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            },
            icon: const Icon(Icons.vertical_align_top),
          ),
          IconButton(
            tooltip: '跳到底部',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(
                _scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            },
            icon: const Icon(Icons.vertical_align_bottom),
          ),
          IconButton(
            tooltip: _autoRefresh ? '暂停刷新' : '自动刷新',
            onPressed: () {
              setState(() => _autoRefresh = !_autoRefresh);
              _armTimer();
            },
            icon: Icon(
              _autoRefresh
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
          ),
          IconButton(
            tooltip: _sortByChildren
                ? (_sortAsc ? 'Children many→few' : 'Children few→many')
                : (_sortByStatus
                    ? (_sortAsc ? 'Status Z→A' : 'Status A→Z')
                    : (_sortByBranch
                        ? (_sortAsc ? 'Branch Z→A' : 'Branch A→Z')
                        : (_sortByDirty
                            ? (_sortAsc ? 'Dirty first' : 'Clean first')
                            : (_sortByName
                                ? (_sortAsc
                                    ? 'Name Z→A (dirs first)'
                                    : 'Name A→Z (dirs first)')
                                : (_sortByType
                                    ? (_sortAsc
                                        ? '类型 Z→A（目录优先）'
                                        : '类型 A→Z（目录优先）')
                                    : (_sortByPath
                                        ? (_sortAsc
                                            ? 'Path Z→A (dirs first)'
                                            : 'Path A→Z (dirs first)')
                                        : (_sortByMtime
                                            ? (_sortAsc
                                                ? 'Mtime new→old'
                                                : 'Mtime old→new')
                                            : (_sortBySize
                                                ? (_sortAsc
                                                    ? 'Size large→small'
                                                    : 'Size small→large')
                                                : (_sortAsc
                                                    ? 'Sort Z→A (dirs first)'
                                                    : 'Sort A→Z (dirs first)'))))))))),
            onPressed: () {
              setState(() {
                if (!_sortBySize &&
                    !_sortByMtime &&
                    !_sortByPath &&
                    !_sortByType &&
                    !_sortByName &&
                    !_sortByDirty &&
                    !_sortByBranch &&
                    !_sortByStatus &&
                    !_sortByChildren &&
                    _sortAsc) {
                  _sortAsc = false;
                } else if (!_sortBySize &&
                    !_sortByMtime &&
                    !_sortByPath &&
                    !_sortByType &&
                    !_sortByName &&
                    !_sortByDirty &&
                    !_sortByBranch &&
                    !_sortByStatus &&
                    !_sortByChildren &&
                    !_sortAsc) {
                  _sortBySize = true;
                  _sortByMtime = false;
                  _sortByPath = false;
                  _sortByType = false;
                  _sortByName = false;
                  _sortByDirty = false;
                  _sortByBranch = false;
                  _sortByStatus = false;
                  _sortByChildren = false;
                  _sortAsc = true;
                } else if (_sortBySize && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortBySize && !_sortAsc) {
                  _sortBySize = false;
                  _sortByMtime = true;
                  _sortByPath = false;
                  _sortByType = false;
                  _sortByName = false;
                  _sortByDirty = false;
                  _sortByBranch = false;
                  _sortByStatus = false;
                  _sortByChildren = false;
                  _sortAsc = true;
                } else if (_sortByMtime && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByMtime && !_sortAsc) {
                  _sortBySize = false;
                  _sortByMtime = false;
                  _sortByPath = true;
                  _sortByType = false;
                  _sortByName = false;
                  _sortByDirty = false;
                  _sortByBranch = false;
                  _sortByStatus = false;
                  _sortByChildren = false;
                  _sortAsc = true;
                } else if (_sortByPath && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByPath && !_sortAsc) {
                  _sortBySize = false;
                  _sortByMtime = false;
                  _sortByPath = false;
                  _sortByType = true;
                  _sortByName = false;
                  _sortByDirty = false;
                  _sortByBranch = false;
                  _sortByStatus = false;
                  _sortByChildren = false;
                  _sortAsc = true;
                } else if (_sortByType && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByType && !_sortAsc) {
                  _sortBySize = false;
                  _sortByMtime = false;
                  _sortByPath = false;
                  _sortByType = false;
                  _sortByName = true;
                  _sortByDirty = false;
                  _sortByBranch = false;
                  _sortByStatus = false;
                  _sortByChildren = false;
                  _sortAsc = true;
                } else if (_sortByName && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByName && !_sortAsc) {
                  _sortBySize = false;
                  _sortByMtime = false;
                  _sortByPath = false;
                  _sortByType = false;
                  _sortByName = false;
                  _sortByDirty = true;
                  _sortByBranch = false;
                  _sortByStatus = false;
                  _sortByChildren = false;
                  _sortAsc = true;
                } else if (_sortByDirty && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByDirty && !_sortAsc) {
                  _sortBySize = false;
                  _sortByMtime = false;
                  _sortByPath = false;
                  _sortByType = false;
                  _sortByName = false;
                  _sortByDirty = false;
                  _sortByBranch = true;
                  _sortByStatus = false;
                  _sortByChildren = false;
                  _sortAsc = true;
                } else if (_sortByBranch && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByBranch && !_sortAsc) {
                  _sortBySize = false;
                  _sortByMtime = false;
                  _sortByPath = false;
                  _sortByType = false;
                  _sortByName = false;
                  _sortByDirty = false;
                  _sortByBranch = false;
                  _sortByStatus = true;
                  _sortByChildren = false;
                  _sortAsc = true;
                } else if (_sortByStatus && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByStatus && !_sortAsc) {
                  _sortBySize = false;
                  _sortByMtime = false;
                  _sortByPath = false;
                  _sortByType = false;
                  _sortByName = false;
                  _sortByDirty = false;
                  _sortByBranch = false;
                  _sortByStatus = false;
                  _sortByChildren = true;
                  _sortAsc = false;
                } else if (_sortByChildren && !_sortAsc) {
                  _sortAsc = true;
                } else {
                  _sortBySize = false;
                  _sortByMtime = false;
                  _sortByPath = false;
                  _sortByType = false;
                  _sortByName = false;
                  _sortByDirty = false;
                  _sortByBranch = false;
                  _sortByStatus = false;
                  _sortByChildren = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(
              _sortByChildren
                  ? Icons.account_tree_outlined
                  : (_sortByStatus
                      ? Icons.flag_outlined
                      : (_sortByBranch
                          ? Icons.call_split
                          : (_sortByDirty
                              ? Icons.change_circle_outlined
                              : (_sortByName
                                  ? Icons.sort_by_alpha
                                  : (_sortByType
                                      ? Icons.category_outlined
                                      : (_sortByPath
                                          ? Icons.route
                                          : (_sortByMtime
                                              ? Icons.schedule
                                              : (_sortBySize
                                                  ? Icons.data_usage
                                                  : (_sortAsc
                                                      ? Icons.sort_by_alpha
                                                      : Icons.sort))))))))),
            ),
          ),
          IconButton(
            tooltip: _wrapLines ? '截断详情' : '换行详情',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
          ),
          IconButton(
            tooltip: '复制内容',
            onPressed: !isFile
                ? null
                : () async {
                    final text = _node?['content']?.toString() ?? '';
                    await Clipboard.setData(ClipboardData(text: text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('文件内容已复制'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: '复制 Git 摘要',
            onPressed: _git == null
                ? null
                : () async {
                    final g = _git!;
                    final files = (g['files'] as List?) ?? const [];
                    final buf = StringBuffer();
                    buf.writeln('branch: ${g['branch'] ?? '—'}');
                    buf.writeln('dirty: ${g['dirty'] ?? g['is_dirty'] ?? '—'}');
                    buf.writeln(
                      'ahead: ${g['ahead'] ?? '—'} behind: ${g['behind'] ?? '—'}',
                    );
                    buf.writeln('changes: ${files.length}');
                    for (final f in files.whereType<Map>()) {
                      final path = (f['path'] ?? f['file'] ?? '').toString();
                      final status =
                          (f['status'] ?? f['code'] ?? '').toString();
                      if (path.isEmpty) continue;
                      buf.writeln('$status $path');
                    }
                    await Clipboard.setData(
                      ClipboardData(text: buf.toString()),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Git 摘要已复制（${files.length} 个文件）',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.account_tree_outlined),
          ),
          IconButton(
            tooltip: 'Git 对比',
            onPressed: () => _openDiff(isFile ? _path : null),
            icon: const Icon(Icons.difference_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Git 操作',
            icon: const Icon(Icons.commit_outlined),
            onSelected: (action) async {
              switch (action) {
                case 'commit':
                  await _gitCommit();
                  break;
                case 'push':
                  await _gitPush();
                  break;
                case 'pull':
                  await _gitPull();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'commit',
                child: ListTile(
                  leading: Icon(Icons.commit),
                  title: Text(AppStrings.gitCommit),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'push',
                child: ListTile(
                  leading: Icon(Icons.upload),
                  title: Text(AppStrings.gitPush),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'pull',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('拉取'),
                  dense: true,
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: AppStrings.refresh,
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: cs.errorContainer,
              child: ListTile(
                dense: true,
                title: Text(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
                ),
              ),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: _breadcrumbChips()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('all', 'All'),
                  ('dir', 'Dirs'),
                  ('file', 'Files'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _typeFilter == f.$1,
                    onSelected: (_) => setState(() => _typeFilter = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
                FilterChip(
                  label: const Text(
                    'Hide empty',
                    style: TextStyle(fontSize: 12),
                  ),
                  selected: _hideEmpty,
                  onSelected: (_) => setState(() => _hideEmpty = !_hideEmpty),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text(AppStrings.wrap, style: TextStyle(fontSize: 11)),
                  selected: _wrapLines,
                  onSelected: (_) => setState(() => _wrapLines = !_wrapLines),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text(AppStrings.regex, style: TextStyle(fontSize: 11)),
                  selected: _queryRegex,
                  onSelected: (_) => setState(() => _queryRegex = !_queryRegex),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text(AppStrings.matchCase, style: TextStyle(fontSize: 11)),
                  selected: _queryCase,
                  onSelected: (_) => setState(() => _queryCase = !_queryCase),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text(AppStrings.autoRefresh, style: TextStyle(fontSize: 11)),
                  selected: _autoRefresh,
                  onSelected: (_) {
                    setState(() => _autoRefresh = !_autoRefresh);
                    _armTimer();
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final f in const [
                  ('', '任意扩展名'),
                  ('md', 'md'),
                  ('dart', 'dart'),
                  ('py', 'py'),
                  ('json', 'json'),
                  ('other', 'other'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 11)),
                    selected: _extFilter == f.$1,
                    onSelected: (_) => setState(() => _extFilter = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.folder_open, size: 20),
            title: Text(
              _path.isEmpty ? '/' : '/$_path',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            subtitle: Text(
              _git == null
                  ? 'readonly host tree'
                  : 'git ${_git!['branch'] ?? '?'} · ${(_git!['files'] as List?)?.length ?? 0} changes (mock)',
              style: const TextStyle(fontSize: 11),
              maxLines: _wrapLines ? 6 : 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
            trailing: TextButton(
              onPressed: () => _openDiff(),
              child: const Text('对比'),
            ),
          ),
          if (_git != null &&
              (_git!['files'] is List) &&
              (_git!['files'] as List).isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in (_git!['files'] as List).whereType<Map>())
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${f['status'] ?? '?'} ${f['path'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        onPressed: () => _openDiff(f['path']?.toString()),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          if (!isFile)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _filterCtrl,
                decoration: InputDecoration(
                  hintText: _queryRegex
                      ? (_queryCase
                          ? 'Filter (regex · case)'
                          : 'Filter (regex)')
                      : (_queryCase
                          ? 'Filter (case-sensitive)'
                          : 'Filter files in this folder'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: IconButton(
                    tooltip: _queryRegex
                        ? (_queryCase
                            ? '正则 · 大小写 开（长按恢复普通筛选）'
                            : '正则 · 大小写 关（长按恢复普通筛选）')
                        : (_queryCase
                            ? '区分大小写（长按切换正则）'
                            : '不区分大小写（长按切换正则）'),
                    icon: Icon(
                      _queryRegex
                          ? Icons.code
                          : (_queryCase ? Icons.text_fields : Icons.search),
                      size: 18,
                    ),
                    onPressed: () => setState(() => _queryCase = !_queryCase),
                    onLongPress: () =>
                        setState(() => _queryRegex = !_queryRegex),
                  ),
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _filterCtrl.clear();
                            setState(() => _filter = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(),
              child: isFile
                  ? ListView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if ((node?['content']?.toString() ?? '').isNotEmpty &&
                            (_path.endsWith('.md') ||
                                _path.endsWith('.markdown')))
                          MarkdownLite(node?['content']?.toString() ?? '')
                        else if ((node?['content']?.toString() ?? '')
                                .isNotEmpty &&
                            _codeLangFor(_path) != null)
                          MarkdownLite(
                            '```${_codeLangFor(_path)}\n${node?['content']?.toString() ?? ''}\n```',
                          )
                        else
                          SelectableText(
                            node?['content']?.toString() ?? '',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                      ],
                    )
                  : ListView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (_path.isNotEmpty)
                          ListTile(
                            leading: const Icon(Icons.arrow_upward),
                            title: const Text('..'),
                            onTap: () => _load(path: parent ?? ''),
                          ),
                        if (entries.isEmpty && !_loading)
                          const ListTile(title: Text('空目录')),
                        if (entries.isNotEmpty &&
                            _filter.trim().isNotEmpty &&
                            _visibleEntries.isEmpty)
                          const ListTile(
                            title: Text('没有匹配的条目'),
                          ),
                        for (final e in _visibleEntries)
                          ListTile(
                            leading: Icon(
                              e['type'] == 'dir'
                                  ? Icons.folder
                                  : Icons.insert_drive_file_outlined,
                            ),
                            title: Text(e['name']?.toString() ?? ''),
                            subtitle: e['type'] == 'file'
                                ? Text(
                                    '${e['size'] ?? '?'} B · ${e['name'] ?? ''}',
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: _wrapLines ? 4 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: true,
                                  )
                                : Text(
                                    'directory · ${e['name'] ?? ''}',
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: _wrapLines ? 4 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: true,
                                  ),
                            onTap: () => _openEntry(e),
                            onLongPress: () async {
                              final name = e['name']?.toString() ?? '';
                              final p = _path.isEmpty ? name : '$_path/$name';
                              await Clipboard.setData(ClipboardData(text: p));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('已复制 $p'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                            trailing: e['type'] == 'file'
                                ? IconButton(
                                    tooltip: '对比',
                                    icon: const Icon(
                                      Icons.difference_outlined,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      final name = e['name']?.toString() ?? '';
                                      final p =
                                          _path.isEmpty ? name : '$_path/$name';
                                      _openDiff(p);
                                    },
                                  )
                                : null,
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
