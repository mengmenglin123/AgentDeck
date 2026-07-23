import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/discovered_agent.dart';
import '../services/ssh_bootstrap_service.dart';
import '../services/ssh_discovery_service.dart';
import '../utils/security.dart';

class SshDiscoveryScreen extends StatefulWidget {
  const SshDiscoveryScreen({
    super.key,
    required this.initialHost,
    this.service,
    this.bootstrapService,
  });

  final String initialHost;
  final SshDiscoveryService? service;
  final SshBootstrapService? bootstrapService;

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
  bool _installBusy = false;
  String? _error;
  SshDiscoveryResult? _result;
  CompanionInstallResult? _installResult;
  CompanionHostConfig? _hostConfig;

  SshDiscoveryService get _service =>
      widget.service ?? SshDiscoveryService();

  SshBootstrapService get _bootstrapService =>
      widget.bootstrapService ?? SshBootstrapService();

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

  Future<void> _installCompanion() async {
    final result = _result;
    if (result == null) return;
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'SSH 端口无效');
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('安装服务器 Companion？'),
            content: const Text(
              '将安装到当前 SSH 用户的 ~/.local/share/huanhermes，\n\n'
              '不会使用 sudo，不会修改 Agent 渠道或密钥，也不会自动启动服务。\n\n'
              '安装包会先上传并校验 SHA-256，然后原子切换版本；失败不会替换已有版本。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认安装'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _installBusy = true;
      _error = null;
      _installResult = null;
    });
    try {
      final installed = await _bootstrapService.install(
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
      setState(() => _installResult = installed);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Security.redactText(error.toString()));
    } finally {
      if (mounted) setState(() => _installBusy = false);
    }
  }

  Future<void> _configureCompanion() async {
    if (_installResult == null) return;
    setState(() {
      _installBusy = true;
      _error = null;
    });
    try {
      final config = await _bootstrapService.configure(
        host: _host.text,
        port: int.parse(_port.text.trim()),
        username: _username.text,
        password: _usePrivateKey ? null : _password.text,
        privateKeyPem: _usePrivateKey ? _privateKey.text : null,
        privateKeyPassphrase:
            _usePrivateKey && _passphrase.text.isNotEmpty
                ? _passphrase.text
                : null,
        verifyHostKey: _verifyHostKey,
      );
      if (mounted) setState(() => _hostConfig = config);
    } catch (error) {
      if (mounted) setState(() => _error = Security.redactText(error.toString()));
    } finally {
      if (mounted) setState(() => _installBusy = false);
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
            enabled: !_busy && !_installBusy,
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
                  enabled: !_busy && !_installBusy,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _port,
                  enabled: !_busy && !_installBusy,
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
            onSelectionChanged: _busy || _installBusy
                ? null
                : (selection) =>
                    setState(() => _usePrivateKey = selection.first),
          ),
          const SizedBox(height: 12),
          if (!_usePrivateKey)
            TextField(
              controller: _password,
              enabled: !_busy && !_installBusy,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'SSH 密码（不会保存）',
                suffixIcon: IconButton(
                  onPressed: _installBusy
                      ? null
                      : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
            )
          else ...[
            TextField(
              controller: _privateKey,
              enabled: !_busy && !_installBusy,
              minLines: 4,
              maxLines: 8,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '私钥 PEM（不会保存）',
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  tooltip: '选择私钥文件',
                  onPressed: _busy || _installBusy ? null : _pickPrivateKey,
                  icon: const Icon(Icons.file_open_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passphrase,
              enabled: !_busy && !_installBusy,
              obscureText: _obscurePassphrase,
              decoration: InputDecoration(
                labelText: '私钥口令（可选）',
                suffixIcon: IconButton(
                  onPressed: _installBusy
                      ? null
                      : () => setState(
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
            onPressed: _busy || _installBusy ? null : _discover,
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
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy || _installBusy ? null : _installCompanion,
              icon: _installBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_for_offline_outlined),
              label: Text(
                _installBusy ? '正在上传并安装 Companion…' : '安装服务器 Companion',
              ),
            ),
            if (_installResult != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: Text('Companion ${_installResult!.version} 已安装'),
                  subtitle: Text(
                    '已原子激活版本。服务尚未自动启动；配置文件：\n'
                    '${_installResult!.configPath}',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy || _installBusy ? null : _configureCompanion,
                icon: const Icon(Icons.settings_backup_restore_outlined),
                label: const Text('初始化 Host 配置并生成令牌'),
              ),
            ],
            if (_hostConfig != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Host 配置已生成'),
                  subtitle: const Text('令牌仅回填当前 App，不会显示在日志或普通提示中。'),
                ),
              ),
            if (result.stderr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '远端提示：${Security.redactText(result.stderr)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(
                context,
                SshDiscoveryResult(
                  host: result.host,
                  remoteVersion: result.remoteVersion,
                  agents: result.agents,
                  hostKey: result.hostKey,
                  stderr: result.stderr,
                  exitCode: result.exitCode,
                  bridgeToken: _hostConfig?.bridgeToken,
                  mgmtToken: _hostConfig?.mgmtToken,
                  bridgePort: _hostConfig?.bridgePort ?? 9810,
                  mgmtPort: _hostConfig?.mgmtPort ?? 9820,
                ),
              ),
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
