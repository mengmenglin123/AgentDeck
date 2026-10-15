import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../theme/app_theme.dart';
import 'app_bootstrap.dart';

/// First widget on screen: shows a lightweight themed loading screen while
/// [bootstrap] runs, then hands over to [HuanHermesApp].
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.bootstrap,
    this.onReady,
  });

  final Future<BootstrapResult> Function() bootstrap;

  /// Called once after the main app's first frame (e.g. to ask for the
  /// notification permission without blocking startup).
  final VoidCallback? onReady;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  BootstrapResult? _result;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final result = await widget.bootstrap();
    if (!mounted) return;
    setState(() => _result = result);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady?.call());
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result == null) return const StartupLoadingApp();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: result.connection),
        ChangeNotifierProvider.value(value: result.theme),
        ChangeNotifierProvider.value(value: result.settings),
      ],
      child: HuanHermesApp(
        startupNotice: result.profilesReset
            ? '本机保存的服务器配置无法读取（可能是重装后系统密钥已变更），已重置，请重新添加服务器。'
            : null,
      ),
    );
  }
}

/// Plain loading screen shown for the (normally sub-second) startup phase.
class StartupLoadingApp extends StatelessWidget {
  const StartupLoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HuanHermes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 16),
              Text('正在启动…', key: Key('startup-loading')),
            ],
          ),
        ),
      ),
    );
  }
}
