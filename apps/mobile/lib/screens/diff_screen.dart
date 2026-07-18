import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

/// Readonly unified diff viewer (`GET /workspace/diff`).
class DiffScreen extends StatefulWidget {
  const DiffScreen({super.key, required this.config, this.initialPath});

  final ConnectionConfig config;
  final String? initialPath;

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  late final MgmtClient _mgmt = MgmtClient(config: widget.config);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _files = [];
  String? _path;
  String _diff = '';
  bool _lineNums = true;
  bool _wrapLines = false;
  bool _sortAsc = true;
  bool _sortByStatus = false;
  bool _sortByAdds = false;
  bool _sortByDels = false;
  bool _sortByPath = false;
  bool _sortByBasename = false;
  Timer? _timer;
  bool _autoRefresh = false;
  final _scroll = ScrollController();
  final _diffFindCtrl = TextEditingController();
  String _diffQuery = '';
  bool _diffCase = false;
  bool _diffRegex = false;
  final _fileFilterCtrl = TextEditingController();
  String _fileFilter = '';
  bool _fileCase = false;
  bool _fileRegex = false;
  String _statusFilter = '';
  String _pathPrefix = ''; // empty = all

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _loadIndex();
    WidgetsBinding.instance.addPostFrameCallback((_) => _armTimer());
  }

  void _armTimer() {
    _timer?.cancel();
    if (!_autoRefresh || !mounted) return;
    final sec = context.read<AppSettingsController>().dashboardRefreshSec;
    if (sec <= 0) return;
    _timer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted || _loading) return;
      if (_path != null && _path!.isNotEmpty) {
        _loadPath(_path!);
      } else {
        _loadIndex();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _fileFilterCtrl.dispose();
    _diffFindCtrl.dispose();
    super.dispose();
  }

  String _fileStatus(Map<String, dynamic> f) {
    final s = '${f['status'] ?? f['state'] ?? ''}'.trim();
    if (s.isNotEmpty) return s;
    if (f['has_diff'] == true) return 'changed';
    return 'unknown';
  }

  List<String> get _statusOptions {
    final set = <String>{};
    for (final f in _files) {
      set.add(_fileStatus(f));
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> get _pathPrefixOptions {
    final set = <String>{};
    for (final f in _files) {
      final p = '${f['path'] ?? ''}'.replaceAll('\\', '/');
      if (p.isEmpty) continue;
      final i = p.indexOf('/');
      if (i <= 0) continue;
      final seg = p.substring(0, i);
      if (seg.isNotEmpty) set.add(seg);
    }
    final list = set.toList()..sort();
    if (list.length > 8) return list.sublist(0, 8);
    return list;
  }

  bool _pathMatchesPrefix(String path, String prefix) {
    if (prefix.isEmpty) return true;
    final p = path.replaceAll('\\', '/');
    final pref = prefix;
    final pl = p.toLowerCase();
    final prefl = pref.toLowerCase();
    return pl.startsWith(prefl) ||
        pl.contains('/$prefl/') ||
        pl.startsWith('$prefl/') ||
        p.startsWith('$pref/') ||
        p.contains('/$pref/');
  }

  List<Map<String, dynamic>> get _visibleFiles {
    final raw = _fileFilter.trim();
    final q = _fileCase ? raw : raw.toLowerCase();
    var list = List<Map<String, dynamic>>.from(_files);
    if (raw.isNotEmpty) {
      list = list
          .where((f) {
            final p = '${f['path']}';
            if (_fileRegex) {
              try {
                return RegExp(raw, caseSensitive: _fileCase).hasMatch(p);
              } catch (_) {
                return false;
              }
            }
            return (_fileCase ? p : p.toLowerCase()).contains(q);
          })
          .toList();
    }
    if (_statusFilter.isNotEmpty) {
      list = list.where((f) => _fileStatus(f) == _statusFilter).toList();
    }
    if (_pathPrefix.isNotEmpty) {
      list = list
          .where((f) => _pathMatchesPrefix('${f['path'] ?? ''}', _pathPrefix))
          .toList();
    }
    list.sort((a, b) {
      int addsOf(Map x) {
        final v = x['additions'] ?? x['adds'] ?? x['+'] ?? x['insertions'];
        if (v is num) return v.round();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }
      int delsOf(Map x) {
        final v = x['deletions'] ?? x['dels'] ?? x['-'] ?? x['removals'];
        if (v is num) return v.round();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }
      if (_sortByBasename) {
        String baseOf(Map x) {
          final p = (x['path'] ?? x['file'] ?? x['name'] ?? '').toString();
          final i = p.replaceAll('\\', '/').lastIndexOf('/');
          return (i >= 0 ? p.substring(i + 1) : p).toLowerCase();
        }
        final c = baseOf(a).compareTo(baseOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByPath) {
        final pa = '${a['path']}'.toLowerCase();
        final pb = '${b['path']}'.toLowerCase();
        final c = pa.compareTo(pb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByDels) {
        final c = delsOf(a).compareTo(delsOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByAdds) {
        final c = addsOf(a).compareTo(addsOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByStatus) {
        final sa = _fileStatus(a).toLowerCase();
        final sb = _fileStatus(b).toLowerCase();
        final c = sa.compareTo(sb);
        if (c != 0) return _sortAsc ? c : -c;
      }
      final pa = '${a['path']}'.toLowerCase();
      final pb = '${b['path']}'.toLowerCase();
      final c = pa.compareTo(pb);
      return _sortAsc ? c : -c;
    });
    return list;
  }


  Future<void> _copyFilesCsv() async {
    final files = _visibleFiles;
    final buf = StringBuffer();
    buf.writeln('path,status,additions,deletions');
    for (final f in files) {
      final path = '${f['path'] ?? f['file'] ?? ''}'.replaceAll('"', '""');
      final status = '${f['status'] ?? f['state'] ?? ''}'.replaceAll('"', '""');
      final add = f['additions'] ?? f['adds'] ?? f['+'] ?? '';
      final dels = f['deletions'] ?? f['dels'] ?? f['-'] ?? '';
      buf.writeln('"$path","$status",$add,$dels');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${files.length} file row(s)'), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _loadIndex() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _mgmt.workspaceDiff();
      final raw = data['files'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        _files = list;
        _loading = false;
      });
      final target = _path ?? (list.isNotEmpty ? list.first['path']?.toString() : null);
      if (target != null && target.isNotEmpty) {
        await _loadPath(target);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
      });
    }
  }

  Future<void> _loadPath(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _path = path;
    });
    try {
      final data = await _mgmt.workspaceDiff(path: path);
      setState(() {
        _diff = (data['diff'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
      });
    }
  }


  String get _displayDiff {
    final rawQ = _diffQuery.trim();
    if (rawQ.isEmpty) return _diff;
    final lines = _diff.replaceAll('\r\n', '\n').split('\n');
    List<String> hit;
    if (_diffRegex) {
      try {
        final re = RegExp(rawQ, caseSensitive: _diffCase);
        hit = lines.where((l) => re.hasMatch(l)).toList();
      } catch (_) {
        return '(invalid regex: $_diffQuery)';
      }
    } else {
      final q = _diffCase ? rawQ : rawQ.toLowerCase();
      hit = lines
          .where((l) => (_diffCase ? l : l.toLowerCase()).contains(q))
          .toList();
    }
    if (hit.isEmpty) return '(no diff lines match: $_diffQuery)';
    return hit.join('\n');
  }


  ({int adds, int dels, int hunks}) get _diffStats {
    var adds = 0;
    var dels = 0;
    var hunks = 0;
    for (final line in _diff.replaceAll('\r\n', '\n').split('\n')) {
      if (line.startsWith('@@')) {
        hunks += 1;
      } else if (line.startsWith('+') && !line.startsWith('+++')) {
        adds += 1;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        dels += 1;
      }
    }
    return (adds: adds, dels: dels, hunks: hunks);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          () {
            final s = _diffStats;
            final stats = (s.adds == 0 && s.dels == 0)
                ? ''
                : ' · +${s.adds}/-${s.dels}';
            if (_path == null) return 'Git diff$stats';
            if (_diffQuery.trim().isEmpty) return 'Diff · $_path$stats';
            return 'Diff · $_path (find)$stats';
          }(),
        ),
        actions: [
          IconButton(
            tooltip: _lineNums ? 'Hide line numbers' : 'Show line numbers',
            onPressed: () => setState(() => _lineNums = !_lineNums),
            icon: Icon(_lineNums ? Icons.format_list_numbered : Icons.format_list_bulleted),
          ),
          IconButton(
            tooltip: _sortByBasename
                ? (_sortAsc ? 'Basename Z→A' : 'Basename A→Z')
                : (_sortByPath
                    ? (_sortAsc ? 'Path Z→A' : 'Path A→Z')
                    : (_sortByDels
                        ? (_sortAsc ? 'Dels high→low' : 'Dels low→high')
                        : (_sortByAdds
                            ? (_sortAsc ? 'Adds high→low' : 'Adds low→high')
                            : (_sortByStatus
                                ? (_sortAsc ? 'Status Z→A' : 'Status A→Z')
                                : (_sortAsc ? 'Path Z→A' : 'Path A→Z'))))),
            onPressed: () {
              setState(() {
                if (!_sortByStatus && !_sortByAdds && !_sortByDels && !_sortByPath && !_sortByBasename && _sortAsc) {
                  _sortAsc = false;
                } else if (!_sortByStatus && !_sortByAdds && !_sortByDels && !_sortByPath && !_sortByBasename && !_sortAsc) {
                  _sortByStatus = true;
                  _sortByAdds = false;
                  _sortByDels = false;
                  _sortByPath = false;
                  _sortByBasename = false;
                  _sortAsc = true;
                } else if (_sortByStatus && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByStatus && !_sortAsc) {
                  _sortByStatus = false;
                  _sortByAdds = true;
                  _sortByDels = false;
                  _sortByPath = false;
                  _sortByBasename = false;
                  _sortAsc = false;
                } else if (_sortByAdds && !_sortAsc) {
                  _sortAsc = true;
                } else if (_sortByAdds && _sortAsc) {
                  _sortByStatus = false;
                  _sortByAdds = false;
                  _sortByDels = true;
                  _sortByPath = false;
                  _sortByBasename = false;
                  _sortAsc = false;
                } else if (_sortByDels && !_sortAsc) {
                  _sortAsc = true;
                } else if (_sortByDels && _sortAsc) {
                  _sortByStatus = false;
                  _sortByAdds = false;
                  _sortByDels = false;
                  _sortByPath = true;
                  _sortByBasename = false;
                  _sortAsc = true;
                } else if (_sortByPath && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByPath && !_sortAsc) {
                  _sortByStatus = false;
                  _sortByAdds = false;
                  _sortByDels = false;
                  _sortByPath = false;
                  _sortByBasename = true;
                  _sortAsc = true;
                } else if (_sortByBasename && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortByStatus = false;
                  _sortByAdds = false;
                  _sortByDels = false;
                  _sortByPath = false;
                  _sortByBasename = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortByBasename
                ? Icons.insert_drive_file_outlined
                : (_sortByPath
                    ? Icons.route
                    : (_sortByDels
                        ? Icons.remove_circle_outline
                        : (_sortByAdds
                            ? Icons.add_box_outlined
                            : (_sortByStatus
                                ? Icons.flag_outlined
                                : (_sortAsc ? Icons.sort_by_alpha : Icons.sort)))))),
          ),

          IconButton(
            tooltip: _wrapLines ? 'No wrap' : 'Wrap lines',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.horizontal_rule),
          ),
          IconButton(
            tooltip: 'Jump to top',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            },
            icon: const Icon(Icons.vertical_align_top),
          ),
          IconButton(
            tooltip: 'Jump to end',
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
            tooltip: 'Copy path',
            onPressed: _path == null || _path!.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _path!));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Path copied'), duration: Duration(seconds: 1)),
                      );
                    }
                  },
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: 'Copy diff',
            onPressed: _diff.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _diff));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Diff copied'), duration: Duration(seconds: 1)),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copy files CSV',
            onPressed: _files.isEmpty ? null : _copyFilesCsv,
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _autoRefresh ? 'Pause auto-refresh' : 'Auto-refresh',
            onPressed: () {
              setState(() => _autoRefresh = !_autoRefresh);
              _armTimer();
            },
            icon: Icon(_autoRefresh ? Icons.pause_circle_outline : Icons.play_circle_outline),
          ),


          IconButton(onPressed: _loading ? null : _loadIndex, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: TextField(
                controller: _fileFilterCtrl,
                decoration: InputDecoration(
                  hintText: _fileRegex
                      ? (_fileCase
                          ? 'Filter paths (regex · case)'
                          : 'Filter paths (regex)')
                      : (_fileCase
                          ? 'Filter paths (case-sensitive)'
                          : 'Filter changed files'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: IconButton(
                    tooltip: _fileRegex
                        ? (_fileCase
                            ? 'Regex · case on (long-press: plain filter)'
                            : 'Regex · case off (long-press: plain filter)')
                        : (_fileCase
                            ? 'Case-sensitive (long-press: regex)'
                            : 'Case-insensitive (long-press: regex)'),
                    icon: Icon(
                      _fileRegex
                          ? Icons.code
                          : (_fileCase ? Icons.text_fields : Icons.search),
                      size: 18,
                    ),
                    onPressed: () => setState(() => _fileCase = !_fileCase),
                    onLongPress: () => setState(() => _fileRegex = !_fileRegex),
                  ),
                  suffixIcon: _fileFilter.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _fileFilterCtrl.clear();
                            setState(() => _fileFilter = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _fileFilter = v),
              ),
            ),
          if (_files.isNotEmpty && _statusOptions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('All', style: TextStyle(fontSize: 11)),
                    selected: _statusFilter.isEmpty,
                    onSelected: (_) => setState(() => _statusFilter = ''),
                  ),
                  for (final s in _statusOptions)
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(s, style: const TextStyle(fontSize: 11)),
                      selected: _statusFilter == s,
                      onSelected: (_) => setState(() {
                        _statusFilter = _statusFilter == s ? '' : s;
                      }),
                    ),
                ],
              ),
            ),
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Any path', style: TextStyle(fontSize: 11)),
                    selected: _pathPrefix.isEmpty,
                    onSelected: (_) => setState(() => _pathPrefix = ''),
                  ),
                  for (final pref in _pathPrefixOptions)
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(pref, style: const TextStyle(fontSize: 11)),
                      selected: _pathPrefix == pref,
                      onSelected: (_) => setState(() {
                        _pathPrefix = _pathPrefix == pref ? '' : pref;
                      }),
                    ),
                ],
              ),
            ),
          if (_files.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: _visibleFiles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final p = (_visibleFiles[i]['path'] ?? '').toString();
                  final selected = p == _path;
                  final st = _fileStatus(_visibleFiles[i]);
                  Color? avatarColor;
                  if (st == 'M' || st == 'modified') {
                    avatarColor = Colors.orange;
                  } else if (st == 'A' || st == 'added') {
                    avatarColor = Colors.green;
                  } else if (st == 'D' || st == 'deleted') {
                    avatarColor = Colors.red;
                  } else if (st == '?' || st == 'untracked') {
                    avatarColor = Colors.blueGrey;
                  }
                  final badge = st.isEmpty ? '?' : st.substring(0, 1);
                  return ChoiceChip(
                    avatar: CircleAvatar(
                      radius: 8,
                      backgroundColor: avatarColor ?? Colors.grey,
                      child: Text(
                        badge,
                        style: const TextStyle(fontSize: 9, color: Colors.white),
                      ),
                    ),
                    label: Text(p, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) => _loadPath(p),
                  );
                },
              ),
            ),
          if (_diff.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: TextField(
                controller: _diffFindCtrl,
                decoration: InputDecoration(
                  hintText: _diffRegex
                      ? (_diffCase ? 'Find in diff (regex · case)' : 'Find in diff (regex)')
                      : (_diffCase
                          ? 'Find in diff (case-sensitive)'
                          : 'Find in diff (local)'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: IconButton(
                    tooltip: _diffRegex
                        ? (_diffCase
                            ? 'Regex · case on (long-press: plain find)'
                            : 'Regex · case off (long-press: plain find)')
                        : (_diffCase
                            ? 'Case-sensitive (long-press: regex)'
                            : 'Case-insensitive (long-press: regex)'),
                    icon: Icon(
                      _diffRegex
                          ? Icons.code
                          : (_diffCase ? Icons.text_fields : Icons.search),
                      size: 18,
                    ),
                    onPressed: () => setState(() => _diffCase = !_diffCase),
                    onLongPress: () => setState(() => _diffRegex = !_diffRegex),
                  ),
                  suffixIcon: _diffQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _diffFindCtrl.clear();
                            setState(() => _diffQuery = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _diffQuery = v),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadIndex,
              child: _diff.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No diff')),
                      ],
                    )
                  : Container(
                      width: double.infinity,
                      color: Colors.black,
                      child: ListView(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        children: [
                          _DiffText(diff: _displayDiff, showLineNumbers: _lineNums, wrapLines: _wrapLines),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffText extends StatelessWidget {
  const _DiffText({required this.diff, this.showLineNumbers = true, this.wrapLines = false});
  final String diff;
  final bool showLineNumbers;
  final bool wrapLines;

  @override
  Widget build(BuildContext context) {
    final lines = diff.replaceAll('\r\n', '\n').split('\n');
    final rich = SelectableText.rich(
      TextSpan(
        children: [
          for (var i = 0; i < lines.length; i++)
            TextSpan(
              text: showLineNumbers
                  ? ((i + 1).toString().padLeft(4) + '  ' + lines[i] + '\n')
                  : (lines[i] + '\n'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.35,
                color: lines[i].startsWith('+') && !lines[i].startsWith('+++')
                    ? const Color(0xFF81C784)
                    : lines[i].startsWith('-') && !lines[i].startsWith('---')
                        ? const Color(0xFFE57373)
                        : lines[i].startsWith('@@')
                            ? const Color(0xFF64B5F6)
                            : const Color(0xFFB0BEC5),
              ),
            ),
        ],
      ),
    );
    if (wrapLines) return rich;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: rich,
    );

  }
}
