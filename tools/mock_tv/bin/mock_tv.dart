import 'dart:async';
import 'dart:io';

import 'package:mock_webos_tv/mock_webos_tv.dart';

Future<void> main(List<String> args) async {
  final requestedPort = int.tryParse(_option(args, '--port') ?? '') ?? 3000;
  final pairing = _option(args, '--pairing') ?? 'accept';
  final volume = _option(args, '--volume') ?? 'absolute';
  final secure = args.contains('--secure');

  final tv = MockWebOsTv(
    MockTvConfig(
      pairing: switch (pairing) {
        'deny' => PairingBehaviour.deny,
        'ignore' => PairingBehaviour.ignorePrompt,
        _ => PairingBehaviour.accept,
      },
      volume: volume == 'arc' ? VolumeMode.arcExternal : VolumeMode.absolute,
      secure: secure,
      certificatePath: _option(args, '--cert'),
      privateKeyPath: _option(args, '--key'),
    ),
  );

  if (secure &&
      (tv.config.certificatePath == null || tv.config.privateKeyPath == null)) {
    stderr.writeln('--secure needs --cert and --key (PEM files).');
    exitCode = 2;
    return;
  }

  await tv.start(port: requestedPort < 0 ? 0 : requestedPort);
  stdout.writeln('Mock LG webOS TV listening on ${tv.wsEndpoint}');
  stdout.writeln('pairing: $pairing · volume: $volume · secure: $secure');
  stdout.writeln('Press Ctrl+C to stop.');

  final done = Completer<void>();
  ProcessSignal.sigint.watch().listen((_) {
    if (!done.isCompleted) done.complete();
  });
  await done.future;
  await tv.stop();
}

String? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}
