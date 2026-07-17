import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/models/connection_config.dart';

void main() {
  test('builds mgmt and redacted bridge urls', () {
    final c = ConnectionConfig(
      host: '10.0.0.2',
      bridgePort: 9810,
      mgmtPort: 9820,
      bridgeToken: 'secret-bridge',
      mgmtToken: 'secret-mgmt',
      useTls: false,
      deviceId: 'abc123',
    );
    expect(c.mgmtBaseUrl, 'http://10.0.0.2:9820/api/v1');
    expect(c.bridgeWsUrl, contains('token=secret-bridge'));
    expect(c.bridgeWsUrlRedacted, contains('token=***'));
    expect(c.bridgeWsUrlRedacted, isNot(contains('secret-bridge')));
  });

  test('round-trips public+secret json', () {
    final c = ConnectionConfig(
      host: 'example.com',
      useTls: true,
      bridgeToken: 'b',
      mgmtToken: 'm',
      deviceId: 'dev1',
    );
    final restored = ConnectionConfig.fromJson(c.toJson());
    expect(restored.host, 'example.com');
    expect(restored.useTls, isTrue);
    expect(restored.bridgeToken, 'b');
    expect(restored.mgmtToken, 'm');
    expect(restored.mgmtBaseUrl, 'https://example.com:9820/api/v1');
  });

  test('parses pairing uri without wiping merge tokens', () {
    final parsed = ConnectionConfig.tryParsePairingUri(
      'huanhermes://connect?host=10.0.2.2&bridge=19810&mgmt=19820&tls=0',
    );
    expect(parsed, isNotNull);
    expect(parsed!.host, '10.0.2.2');
    expect(parsed.bridgePort, 19810);
    expect(parsed.mgmtPort, 19820);
    expect(parsed.useTls, isFalse);
    expect(parsed.bridgeToken, isEmpty);

    final base = ConnectionConfig(
      host: 'old',
      bridgeToken: 'keep-b',
      mgmtToken: 'keep-m',
    );
    final merged = base.mergePairing(parsed);
    expect(merged.host, '10.0.2.2');
    expect(merged.bridgeToken, 'keep-b');
    expect(merged.mgmtToken, 'keep-m');
  });

  test('rejects non-pairing text', () {
    expect(ConnectionConfig.tryParsePairingUri('https://example.com'), isNull);
    expect(ConnectionConfig.tryParsePairingUri(''), isNull);
  });
}
