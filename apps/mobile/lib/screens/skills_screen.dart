import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/connection_config.dart';
import '../services/catalog_state.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import '../utils/query_match.dart';
import '../l10n/app_strings.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key, required this.config, this.project});
  final ConnectionConfig config;
  final String? project;

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  late final CatalogState<List<Map<String, dynamic>>> _catalog;
  bool get loading => _catalog.loading;
  String? get error => _catalog.error;
  List<Map<String, dynamic>> get skills => _catalog.value ?? const [];
  final _q = TextEditingController();
  String _query = '';
  bool _queryCase = false;
  bool _queryRegex = false;
  String _source = '';
  String _category = '';
  String _tag = ''; // empty=all
  bool _wrapLines = false;
  bool _sortBySource = false;
  bool _sortByDesc = false;
  bool _sortById = false;
  bool _sortByTags = false;
  bool _sortByPath = false;
  bool _sortByEnabled = false;
  bool _sortByName = false;
  bool _sortAsc = true;
  final _scroll = ScrollController();
  bool get _autoRefresh => _catalog.autoRefresh;

  @override
  void initState() {
    super.initState();
    _catalog = CatalogState(
      loader: _fetch,
      errorMapper: (error) => Security.redactText(error.toString()),
    )..addListener(_onCatalogChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant SkillsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project != widget.project ||
        oldWidget.config != widget.config) {
      _catalog.updateLoader(_fetch);
    }
  }

  void _onCatalogChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalogChanged);
    _catalog.dispose();
    _scroll.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetch() {
    return MgmtClient(
      config: widget.config,
    ).listSkills(project: widget.project);
  }

  Future<void> _load() => _catalog.refresh();

  List<Map<String, dynamic>> get _filtered {
    final rawQ = _query.trim();
    final list = skills.where((s) {
      final src = (s['source'] ?? '').toString().toLowerCase();
      if (_source.isNotEmpty) {
        if (_source == 'other') {
          final known = src.contains('builtin') ||
              src.contains('built-in') ||
              src.contains('user') ||
              src.contains('project') ||
              src.contains('plugin') ||
              src.contains('host');
          if (known) return false;
        } else if (!src.contains(_source)) {
          return false;
        }
      }
      if (_category.isNotEmpty) {
        final cat = (s['category'] ?? '').toString().toLowerCase();
        if (_category == 'other') {
          final known = cat.contains('github') ||
              cat.contains('software') ||
              cat.contains('autonomous') ||
              cat.contains('memory') ||
              cat.contains('devops') ||
              cat.contains('research');
          if (known) return false;
        } else if (!cat.contains(_category)) {
          return false;
        }
      }
      if (_tag.isNotEmpty) {
        final tagsRaw = s['tags'] is List
            ? (s['tags'] as List).join(' ')
            : (s['tags'] ?? s['labels'] ?? '');
        final tags = tagsRaw.toString().toLowerCase();
        if (_tag == 'other') {
          final known = tags.contains('hermes') ||
              tags.contains('git') ||
              tags.contains('pr') ||
              tags.contains('debug') ||
              tags.contains('plan') ||
              tags.contains('memory') ||
              tags.contains('console');
          if (known) return false;
        } else if (!tags.contains(_tag)) {
          return false;
        }
      }
      if (rawQ.isEmpty) return true;
      final tags = s['tags'] is List
          ? (s['tags'] as List).join(' ')
          : (s['tags'] ?? s['labels'] ?? '');
      final hayRaw =
          '${s['name']} ${s['description']} ${s['source']} ${s['id']} ${s['path']} ${s['category']} $tags';
      return QueryMatch.matches(
        hayRaw,
        rawQ,
        caseSensitive: _queryCase,
        regex: _queryRegex,
      );
    }).toList();
    list.sort((a, b) {
      String tagsOf(Map x) {
        final t = x['tags'] ?? x['labels'] ?? x['categories'];
        if (t is List) return t.map((e) => '$e').join(' ').toLowerCase();
        return (t ?? '').toString().toLowerCase();
      }

      if (_sortByName) {
        final na = (a['name'] ?? a['id'] ?? '').toString().toLowerCase();
        final nb = (b['name'] ?? b['id'] ?? '').toString().toLowerCase();
        final c = na.compareTo(nb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByEnabled) {
        int enOf(Map x) {
          final v = x['enabled'] ?? x['active'] ?? x['disabled'];
          if (v is bool) {
            if (x.containsKey('disabled') &&
                !x.containsKey('enabled') &&
                !x.containsKey('active')) {
              return v ? 0 : 1;
            }
            return v ? 1 : 0;
          }
          final s = (v ?? '').toString().toLowerCase();
          if (s == 'true' ||
              s == '1' ||
              s == 'yes' ||
              s == 'enabled' ||
              s == 'active') return 1;
          if (s == 'false' || s == '0' || s == 'no' || s == 'disabled')
            return 0;
          return -1;
        }

        final c = enOf(a).compareTo(enOf(b));
        if (c != 0) return _sortAsc ? -c : c; // asc => enabled first
      } else if (_sortByPath) {
        final pa = (a['path'] ?? a['file'] ?? a['slug'] ?? '')
            .toString()
            .toLowerCase();
        final pb = (b['path'] ?? b['file'] ?? b['slug'] ?? '')
            .toString()
            .toLowerCase();
        final c = pa.compareTo(pb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByTags) {
        final c = tagsOf(a).compareTo(tagsOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortById) {
        final ia =
            (a['id'] ?? a['slug'] ?? a['name'] ?? '').toString().toLowerCase();
        final ib =
            (b['id'] ?? b['slug'] ?? b['name'] ?? '').toString().toLowerCase();
        final c = ia.compareTo(ib);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByDesc) {
        final da =
            (a['description'] ?? a['summary'] ?? '').toString().toLowerCase();
        final db =
            (b['description'] ?? b['summary'] ?? '').toString().toLowerCase();
        final c = da.compareTo(db);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortBySource) {
        final sa = (a['source'] ?? '').toString().toLowerCase();
        final sb = (b['source'] ?? '').toString().toLowerCase();
        final c = sa.compareTo(sb);
        if (c != 0) return _sortAsc ? c : -c;
      }
      final na = (a['name'] ?? a['id'] ?? '').toString().toLowerCase();
      final nb = (b['name'] ?? b['id'] ?? '').toString().toLowerCase();
      final c = na.compareTo(nb);
      return _sortAsc ? c : -c;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          items.isEmpty
              ? '技能（只读）'
              : (items.length == skills.length
                  ? '技能 (${items.length})'
                  : '技能 (${items.length}/${skills.length})'),
        ),
        actions: [
          IconButton(
            tooltip: '复制全部',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    for (final s in items) {
                      final name = (s['name'] ?? s['id'] ?? 'skill').toString();
                      final desc =
                          (s['description'] ?? s['summary'] ?? '').toString();
                      buf.writeln('## $name');
                      if (desc.isNotEmpty) buf.writeln(desc);
                      buf.writeln();
                    }
                    await Clipboard.setData(
                      ClipboardData(text: buf.toString()),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已复制 ${items.length} 个技能'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: '复制 CSV',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    buf.writeln('name,source,category,version,description');
                    for (final s in items) {
                      final name = (s['name'] ?? s['id'] ?? 'skill')
                          .toString()
                          .replaceAll(',', ';');
                      final source = (s['source'] ?? '').toString().replaceAll(
                            ',',
                            ';',
                          );
                      final category =
                          (s['category'] ?? '').toString().replaceAll(',', ';');
                      final version =
                          (s['version'] ?? '').toString().replaceAll(',', ';');
                      final desc = (s['description'] ?? s['summary'] ?? '')
                          .toString()
                          .replaceAll(',', ';')
                          .replaceAll('\n', ' ');
                      buf.writeln('$name,$source,$category,$version,$desc');
                    }
                    await Clipboard.setData(
                      ClipboardData(text: buf.toString()),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已复制 CSV（${items.length}）'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _sortByName
                ? (_sortAsc ? '名称 Z→A' : '名称 A→Z')
                : (_sortByEnabled
                    ? (_sortAsc ? '启用优先' : '禁用优先')
                    : (_sortByPath
                        ? (_sortAsc ? '路径 Z→A' : '路径 A→Z')
                        : (_sortByTags
                            ? (_sortAsc ? '标签 Z→A' : '标签 A→Z')
                            : (_sortById
                                ? (_sortAsc ? 'ID Z→A' : 'ID A→Z')
                                : (_sortByDesc
                                    ? (_sortAsc ? '描述 Z→A' : '描述 A→Z')
                                    : (_sortBySource
                                        ? (_sortAsc ? '来源 Z→A' : '来源 A→Z')
                                        : (_sortAsc
                                            ? '名称 Z→A'
                                            : '名称 A→Z'))))))),
            onPressed: () {
              setState(() {
                if (!_sortBySource &&
                    !_sortByDesc &&
                    !_sortById &&
                    !_sortByTags &&
                    !_sortByPath &&
                    !_sortByEnabled &&
                    !_sortByName &&
                    _sortAsc) {
                  _sortAsc = false;
                } else if (!_sortBySource &&
                    !_sortByDesc &&
                    !_sortById &&
                    !_sortByTags &&
                    !_sortByPath &&
                    !_sortByEnabled &&
                    !_sortByName &&
                    !_sortAsc) {
                  _sortBySource = true;
                  _sortByDesc = false;
                  _sortById = false;
                  _sortByTags = false;
                  _sortByPath = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortBySource && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortBySource && !_sortAsc) {
                  _sortBySource = false;
                  _sortByDesc = true;
                  _sortById = false;
                  _sortByTags = false;
                  _sortByPath = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortByDesc && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByDesc && !_sortAsc) {
                  _sortBySource = false;
                  _sortByDesc = false;
                  _sortById = true;
                  _sortByTags = false;
                  _sortByPath = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortById && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortById && !_sortAsc) {
                  _sortBySource = false;
                  _sortByDesc = false;
                  _sortById = false;
                  _sortByTags = true;
                  _sortByPath = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortByTags && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByTags && !_sortAsc) {
                  _sortBySource = false;
                  _sortByDesc = false;
                  _sortById = false;
                  _sortByTags = false;
                  _sortByPath = true;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortByPath && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByPath && !_sortAsc) {
                  _sortBySource = false;
                  _sortByDesc = false;
                  _sortById = false;
                  _sortByTags = false;
                  _sortByPath = false;
                  _sortByEnabled = true;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortByEnabled && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByEnabled && !_sortAsc) {
                  _sortBySource = false;
                  _sortByDesc = false;
                  _sortById = false;
                  _sortByTags = false;
                  _sortByPath = false;
                  _sortByEnabled = false;
                  _sortByName = true;
                  _sortAsc = true;
                } else if (_sortByName && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortBySource = false;
                  _sortByDesc = false;
                  _sortById = false;
                  _sortByTags = false;
                  _sortByPath = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(
              _sortByName
                  ? Icons.sort_by_alpha
                  : (_sortByEnabled
                      ? Icons.toggle_on_outlined
                      : (_sortByPath
                          ? Icons.folder_open
                          : (_sortByTags
                              ? Icons.sell_outlined
                              : (_sortById
                                  ? Icons.tag
                                  : (_sortByDesc
                                      ? Icons.notes
                                      : (_sortBySource
                                          ? Icons.source_outlined
                                          : (_sortAsc
                                              ? Icons.sort_by_alpha
                                              : Icons.sort))))))),
            ),
          ),
          IconButton(
            tooltip: _wrapLines ? '截断详情' : '换行详情',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
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
              _catalog.setAutoRefresh(!_autoRefresh);
            },
            icon: Icon(
              _autoRefresh
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
          ),
          IconButton(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final f in const [
                            ('', '全部'),
                            ('builtin', '内置'),
                            ('user', '用户'),
                            ('project', AppStrings.sortByProject),
                            ('plugin', '插件'),
                            ('host', '主机'),
                            ('other', '其他'),
                          ])
                            FilterChip(
                              label: Text(
                                f.$2,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: _source == f.$1,
                              onSelected: (_) => setState(() => _source = f.$1),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final f in const [
                            ('', '全部分类'),
                            ('autonomous', 'autonomous'),
                            ('github', 'github'),
                            ('software', 'software'),
                            ('memory', 'memory'),
                            ('devops', 'devops'),
                            ('research', 'research'),
                            ('other', '其他'),
                          ])
                            FilterChip(
                              label: Text(
                                f.$2,
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: _category == f.$1,
                              onSelected: (_) =>
                                  setState(() => _category = f.$1),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final f in const [
                            ('', '任意标签'),
                            ('hermes', 'hermes'),
                            ('git', 'git'),
                            ('debug', '调试'),
                            ('plan', 'plan'),
                            ('memory', 'memory'),
                            ('other', '其他'),
                          ])
                            FilterChip(
                              label: Text(
                                f.$2,
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: _tag == f.$1,
                              onSelected: (_) => setState(() => _tag = f.$1),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          FilterChip(
                            label: const Text(
                              AppStrings.wrap,
                              style: TextStyle(fontSize: 11),
                            ),
                            selected: _wrapLines,
                            onSelected: (v) => setState(() => _wrapLines = v),
                            visualDensity: VisualDensity.compact,
                          ),
                          FilterChip(
                            label: const Text(
                              AppStrings.regex,
                              style: TextStyle(fontSize: 11),
                            ),
                            selected: _queryRegex,
                            onSelected: (v) => setState(() => _queryRegex = v),
                            visualDensity: VisualDensity.compact,
                          ),
                          FilterChip(
                            label: const Text(
                              AppStrings.matchCase,
                              style: TextStyle(fontSize: 11),
                            ),
                            selected: _queryCase,
                            onSelected: (v) => setState(() => _queryCase = v),
                            visualDensity: VisualDensity.compact,
                          ),
                          FilterChip(
                            label: const Text(
                              AppStrings.autoRefresh,
                              style: TextStyle(fontSize: 11),
                            ),
                            selected: _autoRefresh,
                            onSelected: (v) {
                              _catalog.setAutoRefresh(v);
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        controller: _q,
                        decoration: InputDecoration(
                          hintText: _queryRegex
                              ? (_queryCase ? '筛选（正则 · 大小写）' : '筛选（正则）')
                              : (_queryCase ? '筛选（区分大小写）' : '筛选名称 / 描述 / 来源'),
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
                                  : (_queryCase
                                      ? Icons.text_fields
                                      : Icons.search),
                              size: 18,
                            ),
                            onPressed: () =>
                                setState(() => _queryCase = !_queryCase),
                            onLongPress: () =>
                                setState(() => _queryRegex = !_queryRegex),
                          ),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _q.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    Expanded(
                      child: skills.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  '主机无 GET /skills（或为空）。\nMock Host 会返回示例技能。',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : items.isEmpty
                              ? const Center(child: Text('没有匹配的技能'))
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.separated(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    controller: _scroll,
                                    itemCount: items.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, i) {
                                      final s = items[i];
                                      final name =
                                          (s['name'] ?? 'skill').toString();
                                      final desc =
                                          (s['description'] ?? '').toString();
                                      final source =
                                          (s['source'] ?? '').toString();
                                      final category =
                                          (s['category'] ?? '').toString();
                                      final version =
                                          (s['version'] ?? '').toString();
                                      final meta = [
                                        if (category.isNotEmpty) category,
                                        if (source.isNotEmpty) source,
                                        if (version.isNotEmpty) version,
                                      ].join(' · ');
                                      return ListTile(
                                        leading: const Icon(Icons.extension),
                                        title: Text(name),
                                        subtitle: Text(
                                          [
                                            if (desc.isNotEmpty) desc,
                                            if (meta.isNotEmpty) meta,
                                          ].join('\n'),
                                          maxLines: _wrapLines ? 8 : 3,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: true,
                                        ),
                                        isThreeLine:
                                            desc.isNotEmpty && meta.isNotEmpty,
                                        trailing: IconButton(
                                          tooltip: '复制',
                                          icon:
                                              const Icon(Icons.copy, size: 18),
                                          onPressed: () async {
                                            await Clipboard.setData(
                                              ClipboardData(
                                                text: '$name\n$desc\n$meta'
                                                    .trim(),
                                              ),
                                            );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text('技能已复制'),
                                                  duration:
                                                      Duration(seconds: 1),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                    ),
                  ],
                ),
    );
  }
}
