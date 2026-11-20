import 'client.dart';
import 'credential.dart';
import 'errors.dart';
import 'logger.dart';
import 'register_outcome.dart';
import 'session.dart';
import 'transport.dart';

/// Minimal LG manifest covering the MVP command set.
///
/// Deliberately small: every permission listed is one the app actually uses.
/// `TEST_DEVICE` is what LG uses to authorise a non-store client.
const Map<String, dynamic> defaultManifest = <String, dynamic>{
  'manifestVersion': 1,
  'appVersion': '1.0.0',
  'signed': <String, dynamic>{
    'created': '20260101',
    'appId': 'com.smartremote.lgtv',
    'vendorId': 'com.smartremote',
    'localizedAppNames': <String, String>{'': 'Smart Remote'},
    'permissions': <String>[
      'TEST_DEVICE',
      'CONTROL_AUDIO',
      'CONTROL_DISPLAY',
      'CONTROL_INPUT_JOYSTICK',
      'CONTROL_INPUT_TV',
      'READ_INPUT_DEVICE_LIST',
    ],
  },
  'permissions': <String>[
    'TEST_DEVICE',
    'CONTROL_AUDIO',
    'CONTROL_DISPLAY',
    'CONTROL_INPUT_JOYSTICK',
    'CONTROL_INPUT_TV',
    'READ_INPUT_DEVICE_LIST',
  ],
  'localizedAppNames': <String, String>{'': 'Smart Remote'},
  'localizedVendorNames': <String, String>{'': 'Smart Remote'},
};

/// A paired, connected TV.
class PairedTv {
  PairedTv({
    required this.credential,
    required this.session,
    required this.client,
  });

  final TvCredential credential;
  final SsapSession session;
  final SsapClient client;

  /// Diagnostics only; never logs the key.
  String get certificateFingerprint =>
      session.transport.certificateFingerprint ?? '';

  Future<void> dispose() => session.close();
}

/// Connects, pairs (or restores) and hands back a live session.
///
/// Transport policy: try the secure port first, fall back to plain when the TV
/// refuses `wss` outright. Both the port and scheme that worked are recorded,
/// because the key is only valid on that transport.
class PairingService {
  PairingService({
    required this.transports,
    this.store,
    this.logger = const SsapLogger(),
    this.timeouts = const SsapTimeouts(),
    this.manifest = defaultManifest,
    this.securePort = 3001,
    this.plainPort = 3000,
  });

  final TransportFactory transports;
  final CredentialStore? store;
  final SsapLogger logger;
  final SsapTimeouts timeouts;
  final Map<String, dynamic> manifest;
  final int securePort;
  final int plainPort;

  Future<PairedTv> pair({
    required String host,
    int? port,
    bool? secure,
    String? knownClientKey,
  }) async {
    final candidates = <({int port, bool secure})>[
      if (port != null)
        (port: port, secure: secure ?? (port == securePort))
      else ...[
        (port: securePort, secure: true),
        if (plainPort != securePort) (port: plainPort, secure: false),
      ],
    ];

    SsapError? lastError;
    for (final candidate in candidates) {
      final endpoint = Uri(
        scheme: candidate.secure ? 'wss' : 'ws',
        host: host,
        port: candidate.port,
      );
      final transport = transports(endpoint, policy: CertificatePolicy.native);
      final session = SsapSession(
        transport: transport,
        logger: logger,
        timeouts: timeouts,
      );

      try {
        await session.connect();
      } on TransportException catch (e) {
        lastError = SsapError(
          SsapErrorKind.network,
          e.kind.name,
          e.message,
          uri: endpoint.toString(),
        );
        await session.close();
        continue;
      }

      final outcome = await session.register(
        manifest: manifest,
        clientKey: knownClientKey,
      );

      if (outcome.isSuccess && outcome.clientKey != null) {
        final credential = TvCredential(
          host: host,
          port: candidate.port,
          secure: candidate.secure,
          clientKey: outcome.clientKey!,
          fingerprint: transport.certificateFingerprint,
          lastSeen: DateTime.now(),
        );
        await store?.write(credential);
        return PairedTv(
          credential: credential,
          session: session,
          client: SsapClient(session: session),
        );
      }

      await session.close();
      lastError = outcome.error ??
          SsapError(
            SsapErrorKind.auth,
            'pairing_${outcome.status.name}',
            'Pairing did not complete (${outcome.status.name}).',
          );

      // A denial or a rejected key is a final answer; retrying it on the other
      // transport would put a second prompt on the TV.
      if (outcome.status != RegisterStatus.failed) break;
    }

    throw lastError ??
        SsapError(
          SsapErrorKind.network,
          'unreachable',
          'The TV could not be reached on this network.',
        );
  }
}
