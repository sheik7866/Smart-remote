import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A TV advertised over Bonjour as `_lg-mrt._tcp`.
class BonjourTv {
  const BonjourTv({required this.name, required this.host, this.port});

  final String name;

  /// IPv4 address resolved by `NetService`, or the `.local` host name when no
  /// address could be resolved.
  final String host;
  final int? port;

  bool get hasHost => host.isNotEmpty;

  factory BonjourTv.fromMap(Map<Object?, Object?> map) {
    final name = map['name'];
    final host = map['host'];
    final port = map['port'];
    return BonjourTv(
      name: name is String ? name.trim() : '',
      host: host is String ? host.trim() : '',
      port: port is int ? port : null,
    );
  }

  @override
  String toString() => 'BonjourTv($name @ $host)';
}

/// Dart side of the native discovery helpers.
///
/// Both calls are no-ops on platforms that have no native implementation, so
/// callers can wire them unconditionally:
///
/// * Android needs a `MulticastLock` before SSDP replies arrive reliably.
/// * iOS uses Bonjour because raw multicast needs an Apple entitlement.
class LgDiscovery {
  LgDiscovery({MethodChannel channel = const MethodChannel(channelName)})
      : _channel = channel;

  static const String channelName = 'com.smartremote/lg_discovery';

  final MethodChannel _channel;

  bool get supportsMulticastLock =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get supportsBonjour =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Holds the Wi-Fi multicast lock. Safe to call twice; the native side is
  /// reference-counted as a single lock.
  Future<void> acquireMulticastLock() async {
    if (!supportsMulticastLock) return;
    await _channel.invokeMethod<void>('acquireMulticastLock');
  }

  Future<void> releaseMulticastLock() async {
    if (!supportsMulticastLock) return;
    await _channel.invokeMethod<void>('releaseMulticastLock');
  }

  /// Browses `_lg-mrt._tcp` for [timeout] and returns whatever resolved.
  ///
  /// Returns an empty list on non-iOS platforms rather than throwing, so a
  /// combined discovery sweep can call it unconditionally.
  Future<List<BonjourTv>> browseBonjour({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!supportsBonjour) return const <BonjourTv>[];
    final raw = await _channel.invokeMethod<List<Object?>>(
      'browseBonjour',
      <String, Object>{'timeoutMs': timeout.inMilliseconds},
    );
    if (raw == null) return const <BonjourTv>[];
    final found = <BonjourTv>[
      for (final item in raw)
        if (item is Map) BonjourTv.fromMap(item),
    ];
    return found.where((BonjourTv tv) => tv.hasHost).toList(growable: false);
  }
}
