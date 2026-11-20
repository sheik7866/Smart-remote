import 'discovery_platform_stub.dart'
    if (dart.library.io) 'discovery_platform_io.dart' as platform;
import 'models.dart';

/// Finds TVs on the local network.
///
/// The interface is platform-agnostic: native builds use SSDP, the browser has
/// no UDP at all and returns an [UnsupportedDiscovery] whose reason the UI
/// shows instead of pretending to search.
abstract class RemoteDiscovery {
  /// False in browsers and anywhere multicast cannot work.
  bool get isSupported;

  /// Why discovery is unavailable, when [isSupported] is false.
  String? get unsupportedReason;

  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
  });
}

/// A discovery implementation that cannot search, with a user-facing reason.
class UnsupportedDiscovery implements RemoteDiscovery {
  const UnsupportedDiscovery([
    this.unsupportedReason =
        'Browsers cannot send multicast, so a TV cannot be found automatically.',
  ]);

  @override
  final String? unsupportedReason;

  @override
  bool get isSupported => false;

  @override
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
  }) async =>
      const <DiscoveredTv>[];
}

/// The discovery implementation for the current platform.
RemoteDiscovery createPlatformDiscovery() => platform.createPlatformDiscovery();

/// A discovery sweep that could not run at all, with user-facing copy.
class DiscoveryFailure implements Exception {
  const DiscoveryFailure(this.message);

  final String message;

  @override
  String toString() => 'DiscoveryFailure($message)';
}

/// The SSDP request itself, kept separate so QA can compare it to the protocol
/// notes without reading socket code.
class SsdpSearch {
  static const String multicastAddress = '239.255.255.250';
  static const int multicastPort = 1900;

  /// Search target used by ConnectSDK and documented in `protocol-notes.md`.
  static const String webOsSearchTarget =
      'urn:lge-com:service:webos-second-screen:1';

  static String build({
    String searchTarget = webOsSearchTarget,
    Duration mx = const Duration(seconds: 3),
  }) {
    final seconds = mx.inSeconds < 1 ? 1 : mx.inSeconds;
    return 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $multicastAddress:$multicastPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: $seconds\r\n'
        'ST: $searchTarget\r\n'
        '\r\n';
  }
}

/// One parsed SSDP datagram.
///
/// Header names are lower-cased; unknown headers are retained for diagnostics.
class SsdpResponse {
  SsdpResponse(this.headers, {required this.senderAddress});

  final Map<String, String> headers;
  final String senderAddress;

  /// Parses a response datagram, or returns null when it is not an SSDP reply.
  ///
  /// LG firmware has been observed sending both `HTTP/1.1 200 OK` replies and
  /// `NOTIFY` adverts, so both are accepted.
  static SsdpResponse? tryParse(
    String datagram, {
    required String senderAddress,
  }) {
    final lines = datagram.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return null;
    final status = lines.first.trim().toUpperCase();
    if (!status.startsWith('HTTP/1.1 200') &&
        !status.startsWith('HTTP/1.0 200') &&
        !status.startsWith('NOTIFY')) {
      return null;
    }

    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      if (line.isEmpty) continue;
      final index = line.indexOf(':');
      if (index <= 0) continue;
      final name = line.substring(0, index).trim().toLowerCase();
      final value = line.substring(index + 1).trim();
      if (name.isEmpty) continue;
      headers[name] = value;
    }
    if (headers.isEmpty) return null;
    return SsdpResponse(headers, senderAddress: senderAddress);
  }

  String? get location => headers['location'];

  String? get searchTarget => headers['st'];

  String? get server => headers['server'];

  String? get uniqueServiceName => headers['usn'];

  /// Heuristic used to drop unrelated UPnP devices (routers, printers) that
  /// answer the same multicast request.
  bool get looksLikeWebOs {
    final evidence =
        '${searchTarget ?? ''} ${uniqueServiceName ?? ''} ${server ?? ''}'
            .toLowerCase();
    return evidence.contains('webos') ||
        evidence.contains('lge-com') ||
        evidence.contains('lg electronics') ||
        evidence.contains('lgwebostv');
  }

  /// The address the TV should be reached on: the description URL's host when
  /// present, otherwise the datagram's sender.
  String get host {
    final uri = Uri.tryParse(location ?? '');
    final host = uri?.host;
    if (host != null && host.isNotEmpty) return host;
    return senderAddress;
  }

  DiscoveredTv toDiscoveredTv({String? name, String? modelName}) =>
      DiscoveredTv(
        host: host,
        name: name,
        modelName: modelName,
        location: location,
      );
}
