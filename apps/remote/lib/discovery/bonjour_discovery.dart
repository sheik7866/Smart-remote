import 'package:lg_discovery/lg_discovery.dart';
import 'package:remote_core/remote_core.dart';

/// iOS discovery through Bonjour `_lg-mrt._tcp`.
///
/// This is the path that works without Apple's multicast entitlement. On other
/// platforms it reports itself unsupported, so [CombinedDiscovery] simply skips
/// it.
class BonjourDiscovery implements RemoteDiscovery {
  BonjourDiscovery(this.native);

  final LgDiscovery native;

  @override
  bool get isSupported => native.supportsBonjour;

  @override
  String? get unsupportedReason =>
      isSupported ? null : 'Bonjour discovery is only used on iOS.';

  @override
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
    DiscoveryCancellation? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) return const <DiscoveredTv>[];
    final services = await native.browseBonjour(timeout: timeout);
    if (cancel?.isCancelled ?? false) return const <DiscoveredTv>[];
    return <DiscoveredTv>[
      for (final service in services)
        DiscoveredTv(
          host: service.host,
          name: service.name.isEmpty ? null : service.name,
          source: DiscoverySource.bonjour,
        ),
    ];
  }
}
