import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

void main() {
  test('redacts client keys, IPv4 addresses and long hex secrets', () {
    const raw = '{"client-key":"super-secret"} from 192.168.1.20 '
        'token 0123456789abcdef0123456789abcdef';

    final redacted = SsapLogger.redact(raw);

    expect(redacted, isNot(contains('super-secret')));
    expect(redacted, isNot(contains('192.168.1.20')));
    expect(redacted, isNot(contains('0123456789abcdef0123456789abcdef')));
    expect(redacted, contains('<redacted>'));
    expect(redacted, contains('<ip>'));
    expect(redacted, contains('<secret>'));
  });

  test('disabled logger writes nothing', () {
    final lines = <String>[];
    const SsapLogger(sink: null).debug('ignored');
    const SsapLogger(enabled: false, sink: _collect).debug('ignored');

    expect(lines, isEmpty);
  });

  test('enabled logger writes only redacted lines', () {
    final lines = <String>[];
    final logger = SsapLogger(enabled: true, sink: lines.add);

    logger.debug('paired {"client-key":"secret-key-123"} at 10.0.0.5');

    expect(lines, hasLength(1));
    expect(lines.single, isNot(contains('secret-key-123')));
    expect(lines.single, isNot(contains('10.0.0.5')));
  });

  test('TvCredential.toString never exposes the key', () {
    const credential = TvCredential(
      host: '192.168.1.20',
      port: 3001,
      secure: true,
      clientKey: 'never-print-me',
    );

    expect(credential.toString(), isNot(contains('never-print-me')));
    expect(credential.toString(), contains('<redacted>'));
  });
}

void _collect(String message) {}
