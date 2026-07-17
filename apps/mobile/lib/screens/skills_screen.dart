
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/connection_config.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key, required this.config});
  final ConnectionConfig config;

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> skills = [];
  final _q = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await MgmtClient(config: widget.config).listSkills();
      setState(() {
        skills = list;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = Security.redactText(e.toString());
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return skills;
    return skills.where((s) {
      final hay = '${s['name']} ${s['description']} ${s['source']}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skills (readonly)'),
        actions: [
          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        controller: _q,
                        decoration: InputDecoration(
                          hintText: 'Filter name / description / source',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search, size: 18),
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
                                  'Host has no GET /skills (or empty).\nMock Host returns sample skills.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : items.isEmpty
                              ? const Center(child: Text('No skills match filter'))
                              : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, i) {
                                    final s = items[i];
                                    final name = (s['name'] ?? 'skill').toString();
                                    final desc = (s['description'] ?? '').toString();
                                    final source = (s['source'] ?? '').toString();
                                    return ListTile(
                                      leading: const Icon(Icons.extension),
                                      title: Text(name),
                                      subtitle: Text(
                                        [if (desc.isNotEmpty) desc, if (source.isNotEmpty) source].join('\n'),
                                      ),
                                      isThreeLine: desc.isNotEmpty && source.isNotEmpty,
                                      trailing: IconButton(
                                        tooltip: 'Copy',
                                        icon: const Icon(Icons.copy, size: 18),
                                        onPressed: () async {
                                          await Clipboard.setData(
                                            ClipboardData(text: '$name\n$desc\n$source'.trim()),
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Skill copied'),
                                                duration: Duration(seconds: 1),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    );
                                  },
                                )),
                    ),
                  ],
                ),
    );
  }
}
