import 'dart:async';

import 'discovery_platform_stub.dart'
    if (dart.library.io) 'discovery_platform_io.dart' as platform;
import 'models.dart';

/// A cooperative cancel signal for one discovery sweep.
///
/// A socket that is already connecting cannot be aborted, but every source
/// checks the token between attempts and returns early, so leaving the screen
/// stops the fallback probe from opening further connections.
class DiscoveryCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called; never completes otherwise.
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

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

  /// Runs one sweep.
  ///
  /// [cancel] stops the sweep cooperatively: no further sockets are opened
  /// and the source returns early, so a screen that is gone does not keep
  /// probing the network.
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
    DiscoveryCancellation? cancel,
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
    DiscoveryCancellation? cancel,
  }) async =>
      const <DiscoveredTv>[];
}

/// The discovery implementation for the current platform.
///
/// [onSweepStart] and [onSweepEnd] bracket the multicast sweep so the app can
/// acquire and release the Android multicast lock. On platforms where the hook
/// is meaningless it is ignored.
RemoteDiscovery createPlatformDiscovery({
  Future<void> Function()? onSweepStart,
  Future<void> Function()? onSweepEnd,
}) =>
    platform.createPlatformDiscovery(
      onSweepStart: onSweepStart,
      onSweepEnd: onSweepEnd,
    );

/// The bounded subnet probe for the current platform.
///
/// Native builds get a real socket scanner; browsers get an unsupported source
/// so callers can wire it unconditionally.
RemoteDiscovery createSubnetProbeDiscovery() =>
    platform.createSubnetProbeDiscovery();

/// Runs several discovery sources and merges their results by host.
///
/// One failing source must not hide the TVs another source found: a TV without
/// SSDP replies (iOS without the multicast entitlement) can still answer
/// Bonjour, and a Bonjour failure must not break SSDP.
class CombinedDiscovery implements RemoteDiscovery {
  CombinedDiscovery(this.sources, {this.fallback});

  final List<RemoteDiscovery> sources;

  /// Runs only when every entry in [sources] returns no devices.
  ///
  /// The subnet probe is the slow, low-confidence source, so it must not run
  /// alongside a normal SSDP/Bonjour sweep.
  final RemoteDiscovery? fallback;

  @override
  bool get isSupported =>
      sources.any((RemoteDiscovery source) => source.isSupported) ||
      (fallback?.isSupported ?? false);

  @override
  String? get unsupportedReason {
    if (isSupported) return null;
    for (final source in <RemoteDiscovery>[
      ...sources,
      if (fallback != null) fallback!,
    ]) {
      final reason = source.unsupportedReason;
      if (reason != null) return reason;
    }
    return 'This platform cannot search the network automatically.';
  }

  @override
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
    DiscoveryCancellation? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) return const <DiscoveredTv>[];

    final active = sources
        .where((RemoteDiscovery source) => source.isSupported)
        .toList(growable: false);
    final results =
        await Future.wait(active.map((RemoteDiscovery source) async {
      try {
        return await source.search(timeout: timeout, cancel: cancel);
      } on Object {
        return const <DiscoveredTv>[];
      }
    }));

    final merged = <String, DiscoveredTv>{};
    for (final list in results) {
      _merge(merged, list);
    }

    final probe = fallback;
    final cancelled = cancel?.isCancelled ?? false;
    if (merged.isEmpty && !cancelled && probe != null && probe.isSupported) {
      try {
        _merge(
          merged,
          await probe.search(timeout: timeout, cancel: cancel),
        );
      } on Object {
        // The fallback is best effort; it must not turn "nothing found" into
        // a discovery failure.
      }
    }

    if (cancel?.isCancelled ?? false) return const <DiscoveredTv>[];
    final devices = merged.values.toList()
      ..sort((DiscoveredTv a, DiscoveredTv b) => a.host.compareTo(b.host));
    return devices;
  }

  void _merge(Map<String, DiscoveredTv> merged, Iterable<DiscoveredTv> tvs) {
    for (final tv in tvs) {
      final existing = merged[tv.host];
      // Prefer the entry that carries a name, whichever source found it.
      if (existing == null || (existing.name == null && tv.name != null)) {
        merged[tv.host] = tv;
      }
    }
  }
}

/// Probes private /24 networks for an open webOS WebSocket port.
///
/// This is the last resort when SSDP and Bonjour find nothing. A host with
/// port 3000 or 3001 open is not necessarily a TV, so results are marked
/// [DiscoverySource.subnetProbe] and the UI asks the user to confirm.
///
/// The probe is bounded three ways: only private /24 prefixes are used, at
/// most [maxHosts] addresses are tried, and [search] stops at its timeout.
class SubnetProbeDiscovery implements RemoteDiscovery {
  SubnetProbeDiscovery({
    required this.probe,
    required this.subnetPrefixes,
    this.ports = const <int>[3000, 3001],
    this.concurrency = 48,
    this.maxHosts = 512,
  })  : assert(concurrency > 0, 'concurrency must be positive'),
        assert(maxHosts > 0, 'maxHosts must be positive');

  /// Returns true when [port] accepts a TCP connection on [host].
  final Future<bool> Function(String host, int port) probe;

  /// Private IPv4 /24 prefixes without the trailing octet, e.g. `192.168.1`.
  final Future<List<String>> Function() subnetPrefixes;

  /// Ports the TV listens on: `ws` on 3000 and `wss` on 3001.
  final List<int> ports;

  /// Maximum number of connection attempts in flight at once.
  final int concurrency;

  /// Maximum number of addresses tried in one sweep.
  final int maxHosts;

  @override
  bool get isSupported => true;

  @override
  String? get unsupportedReason => null;

  @override
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
    DiscoveryCancellation? cancel,
  }) async {
    if (timeout <= Duration.zero || (cancel?.isCancelled ?? false)) {
      return const <DiscoveredTv>[];
    }
    final clock = Stopwatch()..start();

    final List<String> prefixes;
    try {
      prefixes = await subnetPrefixes().timeout(timeout);
    } on Object {
      return const <DiscoveredTv>[];
    }

    final hosts = <String>[];
    final seen = <String>{};
    for (final prefix in prefixes) {
      if (prefix.isEmpty) continue;
      for (var last = 1; last <= 254 && hosts.length < maxHosts; last++) {
        final host = '$prefix.$last';
        if (seen.add(host)) hosts.add(host);
      }
    }
    if (hosts.isEmpty) return const <DiscoveredTv>[];

    final found = <String>[];
    var next = 0;

    Future<void> worker() async {
      while (!(cancel?.isCancelled ?? false) && clock.elapsed < timeout) {
        final index = next++;
        if (index >= hosts.length) return;
        final host = hosts[index];
        for (final port in ports) {
          if (cancel?.isCancelled ?? false) return;
          final remaining = timeout - clock.elapsed;
          if (remaining <= Duration.zero) return;
          var open = false;
          try {
            open = await probe(host, port).timeout(remaining);
          } on Object {
            // A refused, unreachable or hung host is simply not a TV.
          }
          if (open) {
            if (!(cancel?.isCancelled ?? false)) found.add(host);
            return;
          }
        }
      }
    }

    final workers = concurrency < hosts.length ? concurrency : hosts.length;
    await Future.wait(<Future<void>>[
      for (var i = 0; i < workers; i++) worker(),
    ]);

    if (cancel?.isCancelled ?? false) return const <DiscoveredTv>[];
    found.sort();
    return <DiscoveredTv>[
      for (final host in found)
        DiscoveredTv(host: host, source: DiscoverySource.subnetProbe),
    ];
  }
}

/// Extracts up to [maxPrefixes] distinct private IPv4 /24 prefixes.
///
/// Dart exposes interface addresses but not netmasks, so a /24 around each
/// private address is the deliberately bounded assumption. Loopback,
/// link-local, public and malformed addresses are ignored.
List<String> privateSubnetPrefixes(
  Iterable<String> addresses, {
  int maxPrefixes = 2,
}) {
  final prefixes = <String>{};
  for (final address in addresses) {
    final parts = address.split('.');
    if (parts.length != 4) continue;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) break;
      octets.add(value);
    }
    if (octets.length != 4) continue;
    final first = octets[0];
    final second = octets[1];
    final isPrivate = first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
    if (!isPrivate) continue;
    prefixes.add('$first.$second.${octets[2]}');
    if (prefixes.length >= maxPrefixes) break;
  }
  return prefixes.toList(growable: false);
}

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
        source: DiscoverySource.ssdp,
      );
}
