import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/services/ssh_bootstrap_service.dart';

void main() {
  test('builds fixed install command only for generated temporary paths', () {
    const path =
        '/tmp/huanhermes-companion-0123456789abcdef0123456789abcdef.tar.gz';
    final command = SshBootstrapService.buildInstallCommand(path);

    expect(command, contains(SshBootstrapService.archiveSha256));
    expect(command, contains('--version \'0.1.202\''));
    expect(command, contains(r'--prefix "$HOME/.local/share/huanhermes"'));
    expect(command, isNot(contains('sudo')));
    expect(command, isNot(contains('systemctl')));

    expect(
      () => SshBootstrapService.buildInstallCommand(
        '/tmp/archive.tar.gz; touch /tmp/owned',
      ),
      throwsA(isA<SshBootstrapException>()),
    );
  });

  test('parses typed companion install marker', () {
    const output = '''noise
HH_COMPANION\t{"version":"0.1.202","release_dir":"/home/u/.local/share/huanhermes/releases/0.1.202","service_path":"/home/u/.config/systemd/user/huanhermes-host.service","config_path":"/home/u/.local/share/huanhermes/config/host.toml","activated":true,"service_started":false}
''';

    final result = SshBootstrapService.parseInstallOutput(output);

    expect(result.version, '0.1.202');
    expect(result.activated, isTrue);
    expect(result.serviceStarted, isFalse);
    expect(result.configPath, endsWith('/config/host.toml'));
  });

  test('rejects malformed or incomplete install markers', () {
    expect(
      () => SshBootstrapService.parseInstallOutput('HH_COMPANION\t{}'),
      throwsA(isA<SshBootstrapException>()),
    );
    expect(
      () => SshBootstrapService.parseInstallOutput('not a marker'),
      throwsA(isA<SshBootstrapException>()),
    );
  });

  test('parses generated Host tokens and ports', () {
    const output =
        'HH_COMPANION_CONFIG\t{"bridge_token":"bridge-secret","mgmt_token":"mgmt-secret","bridge_port":9810,"mgmt_port":9820,"config_path":"/home/u/.local/share/huanhermes/config/host.toml"}';
    final config = SshBootstrapService.parseConfigOutput(output);
    expect(config.bridgeToken, 'bridge-secret');
    expect(config.mgmtToken, 'mgmt-secret');
    expect(config.bridgePort, 9810);
  });
}
