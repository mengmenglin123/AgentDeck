import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/discovered_agent.dart';
import '../services/ssh_discovery_service.dart';
import '../utils/security.dart';

class SshDiscoveryScreen extends StatefulWidget {
  const SshDiscoveryScreen({
    super.key,
    required this.initialHost,
    this.service,
  });

  final String initialHost;
  final SshDiscoveryService? service;

  @override
  State<SshDiscoveryScreen> createState() => _SshDiscoveryScreenState();
}

class _SshDiscoveryScreenState extends State<SshDiscoveryScreen> {
  late final TextEditingController _host;
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _privateKey = TextEditingController();
  final _passphrase = TextEditingController();
  bool _usePrivateKey = false;
  bool _obscurePassword = true;
  bool _obscurePassphrase = true;
  bool _busy = false;
  String? _error;
  SshDiscoveryResult? _result;

  SshDiscoveryService get _service =>
      widget.service ?? SshDiscoveryService();

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.initialHost);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _privateKey.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _pickPrivateKey() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.any,
    );
    if (!mounted || picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = '无法读取私钥文件');
      return;
    }
    if (bytes.length > 256 * 1024) {
      setState(() => _error = '私钥文件过大');
      return;
    }
    try {
      setState(() {
        _privateKey.text = utf8.decode(bytes, allowMalformed: false);
        _error = null;
      });
    } on FormatException {
      setState(() => _error = '私钥文件不是有效的 UTF-8 文本');
    }
  }

  Future<bool> _verifyHostKey(SshHostKey key) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('确认 SSH 主机指纹'),
            content: SelectableText(
              '类型：${key.type}\n\n指纹：\n${key.fingerprint}\n\n'
              '请与服务器管理员提供的指纹核对。首次确认错误可能导致中间人攻击。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('拒绝'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('指纹正确，继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _discover() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'SSH 端口无效');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _service.discover(
        host: _host.text,
        port: port,
        username: _username.text,
        password: _usePrivateKey ? null : _password.text,
        privateKeyPem: _usePrivateKey ? _privateKey.text : null,
        privateKeyPassphrase:
            _usePrivateKey && _passphrase.text.isNotEmpty
                ? _passphrase.text
                : null,
        verifyHostKey: _verifyHostKey,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Security.redactText(error.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('SSH 自动发现 Agent')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'SSH 只用于首次发现服务器上的 Agent。发现完成后，长期控制仍通过 HuanHermes Bridge 与 Management 接口。',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _host,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'SSH 主机',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _username,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _port,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '端口'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('密码')),
              ButtonSegment(value: true, label: Text('私钥')),
            ],
            selected: {_usePrivateKey},
            onSelectionChanged: _busy
                ? null
                : (selection) =>
                    setState(() => _usePrivateKey = selection.first),
          ),
          const SizedBox(height: 12),
          if (!_usePrivateKey)
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'SSH 密码（不会保存）',
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
            )
          else ...[
            TextField(
              controller: _privateKey,
              enabled: !_busy,
              minLines: 4,
              maxLines: 8,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '私钥 PEM（不会保存）',
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  tooltip: '选择私钥文件',
                  onPressed: _busy ? null : _pickPrivateKey,
                  icon: const Icon(Icons.file_open_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passphrase,
              enabled: !_busy,
              obscureText: _obscurePassphrase,
              decoration: InputDecoration(
                labelText: '私钥口令（可选）',
                suffixIcon: IconButton(
                  onPressed: () => setState(
                    () => _obscurePassphrase = !_obscurePassphrase,
                  ),
                  icon: Icon(_obscurePassphrase
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _discover,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.radar_outlined),
            label: Text(_busy ? '正在通过 SSH 探测…' : '连接并自动识别 Agent'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (result != null) ...[
            const SizedBox(height: 20),
            Text(
              '发现 ${result.agents.length} 个 Agent',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${result.remoteVersion} · ${result.hostKey.fingerprint}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (result.agents.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.search_off),
                  title: Text('未发现支持的 Agent'),
                  subtitle: Text('当前识别 codex、claude、hermes；请检查登录用户的 PATH。'),
                ),
              )
            else
              ...result.agents.map(_agentCard),
            if (result.stderr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '远端提示：${Security.redactText(result.stderr)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, result),
              icon: const Icon(Icons.arrow_back),
              label: const Text('应用主机地址并继续配置 Host'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _agentCard(DiscoveredAgent agent) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.smart_toy_outlined),
        title: Text(agent.label),
        subtitle: Text(
          '${agent.version}\n${agent.path}\nDriver: ${agent.driver}\n'
          '能力：${agent.capabilities.join('、')}',
        ),
        isThreeLine: true,
      ),
    );
  }
}
