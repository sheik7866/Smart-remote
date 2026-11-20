/// App-facing remote state, command orchestration and discovery.
///
/// Depends on `webos_ssap` but never on Flutter: the app's widgets talk to
/// [RemoteController] and the snapshot types only.
library;

export 'src/backoff.dart';
export 'src/discovery.dart';
export 'src/latency.dart';
export 'src/models.dart';
export 'src/remote_controller.dart';
