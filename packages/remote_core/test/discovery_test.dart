import 'package:remote_core/remote_core.dart';
import 'package:test/test.dart';

void main() {
  group('M-SEARCH request', () {
    test('uses the documented multicast target and CRLF framing', () {
      final request = SsdpSearch.build(
        mx: const Duration(seconds: 5),
      );
      expect(request, contains('M-SEARCH * HTTP/1.1\r\n'));
      expect(request, contains('HOST: 239.255.255.250:1900\r\n'));
      expect(request, contains('MAN: "ssdp:discover"\r\n'));
      expect(request, contains('MX: 5\r\n'));
      expect(
        request,
        contains('ST: urn:lge-com:service:webos-second-screen:1\r\n'),
      );
      expect(request, endsWith('\r\n\r\n'));
    });
  });

  group('SSDP parsing', () {
    const response = 'HTTP/1.1 200 OK\r\n'
        'CACHE-CONTROL: max-age=1800\r\n'
        'LOCATION: http://192.168.1.44:1990/ssdp/device-desc.xml\r\n'
        'SERVER: WebOS/1.0 UPnP/1.0 LG-WebOS/2.0\r\n'
        'ST: urn:lge-com:service:webos-second-screen:1\r\n'
        'USN: uuid:abc::urn:lge-com:service:webos-second-screen:1\r\n'
        '\r\n';

    test('reads headers case-insensitively and takes the host from LOCATION',
        () {
      final parsed = SsdpResponse.tryParse(
        response,
        senderAddress: '192.168.1.44',
      );
      expect(parsed, isNotNull);
      expect(parsed!.location, 'http://192.168.1.44:1990/ssdp/device-desc.xml');
      expect(parsed.host, '192.168.1.44');
      expect(parsed.looksLikeWebOs, isTrue);
      expect(parsed.toDiscoveredTv(name: 'Living room').displayName,
          'Living room');
    });

    test('falls back to the datagram sender when LOCATION is absent', () {
      final parsed = SsdpResponse.tryParse(
        'HTTP/1.1 200 OK\r\nST: ssdp:all\r\nSERVER: WebOS/1.0\r\n\r\n',
        senderAddress: '10.0.0.9',
      );
      expect(parsed, isNotNull);
      expect(parsed!.host, '10.0.0.9');
    });

    test('ignores unrelated devices and malformed datagrams', () {
      final printer = SsdpResponse.tryParse(
        'HTTP/1.1 200 OK\r\n'
        'LOCATION: http://192.168.1.9:80/desc.xml\r\n'
        'SERVER: Linux/3.14 UPnP/1.0 Printer/1.0\r\n'
        'ST: urn:schemas-upnp-org:device:Printer:1\r\n\r\n',
        senderAddress: '192.168.1.9',
      );
      expect(printer, isNotNull);
      expect(
        printer!.looksLikeWebOs,
        isFalse,
        reason: 'a printer must not be offered as an LG TV',
      );

      expect(
        SsdpResponse.tryParse('', senderAddress: '127.0.0.1'),
        isNull,
      );
      expect(
        SsdpResponse.tryParse('not http at all', senderAddress: '127.0.0.1'),
        isNull,
      );
    });

    test('accepts NOTIFY adverts', () {
      final parsed = SsdpResponse.tryParse(
        'NOTIFY * HTTP/1.1\r\n'
        'LOCATION: http://192.168.1.50:1990/desc.xml\r\n'
        'ST: urn:lge-com:service:webos-second-screen:1\r\n\r\n',
        senderAddress: '192.168.1.50',
      );
      expect(parsed, isNotNull);
      expect(parsed!.looksLikeWebOs, isTrue);
    });
  });

  group('CombinedDiscovery', () {
    test('merges sources by host and keeps the named entry', () async {
      final combined = CombinedDiscovery(<RemoteDiscovery>[
        _StubDiscovery(devices: const <DiscoveredTv>[
          DiscoveredTv(host: '192.168.1.10'),
        ]),
        _StubDiscovery(devices: const <DiscoveredTv>[
          DiscoveredTv(host: '192.168.1.10', name: 'Living room TV'),
          DiscoveredTv(host: '192.168.1.11', name: 'Bedroom'),
        ]),
      ]);

      final tvs = await combined.search();

      expect(tvs, hasLength(2));
      expect(
        tvs.firstWhere((DiscoveredTv tv) => tv.host == '192.168.1.10').name,
        'Living room TV',
      );
    });

    test('one failing source does not hide another source', () async {
      final combined = CombinedDiscovery(<RemoteDiscovery>[
        _StubDiscovery(throws: true),
        _StubDiscovery(devices: const <DiscoveredTv>[
          DiscoveredTv(host: '192.168.1.12', name: 'Kitchen'),
        ]),
      ]);

      final tvs = await combined.search();

      expect(tvs.single.displayName, 'Kitchen');
    });

    test('is unsupported only when every source is unsupported', () {
      final unsupported = CombinedDiscovery(const <RemoteDiscovery>[
        UnsupportedDiscovery('no multicast'),
      ]);
      expect(unsupported.isSupported, isFalse);
      expect(unsupported.unsupportedReason, 'no multicast');

      final mixed = CombinedDiscovery(<RemoteDiscovery>[
        const UnsupportedDiscovery('no multicast'),
        _StubDiscovery(devices: const <DiscoveredTv>[]),
      ]);
      expect(mixed.isSupported, isTrue);
      expect(mixed.unsupportedReason, isNull);
    });
  });

  test('the web-safe default has a user-facing reason', () {
    const discovery = UnsupportedDiscovery();
    expect(discovery.isSupported, isFalse);
    expect(discovery.unsupportedReason, isNotEmpty);
  });
}

class _StubDiscovery implements RemoteDiscovery {
  _StubDiscovery({
    this.devices = const <DiscoveredTv>[],
    this.throws = false,
  });

  final List<DiscoveredTv> devices;
  final bool throws;

  @override
  bool get isSupported => true;

  @override
  String? get unsupportedReason => null;

  @override
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (throws) throw const DiscoveryFailure('offline');
    return devices;
  }
}
