
import 'package:flutter/material.dart';

import '../models/connection_config.dart';
import '../services/mgmt_client.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
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
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              : skills.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Host has no GET /skills (or empty).\nMock Host returns sample skills.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: skills.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = skills[i];
                        return ListTile(
                          leading: const Icon(Icons.extension),
                          title: Text((s['name'] ?? 'skill').toString()),
                          subtitle: Text(
                            '${s['description'] ?? ''}\n${s['source'] ?? ''}',
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
    );
  }
}
