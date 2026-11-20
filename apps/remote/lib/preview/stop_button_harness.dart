/// Preview-only entrypoint for the discovery Stop control.
///
/// This is not the shipping app: the sweep is simulated, nothing touches the
/// network, and the banner says so. The browser target cannot discover TVs
/// (no multicast), so the normal web build never reaches
/// [RemoteStatus.discovering]; this harness exists only to exercise that UI.
///
///     flutter build web --release -t lib/preview/stop_button_harness.dart
library;

import 'package:material_ui/material_ui.dart';
import 'package:remote_core/remote_core.dart';

import '../features/connect/connect_screen.dart';
import '../theme/remote_theme.dart';

void main() => runApp(const StopButtonPreviewApp());

class StopButtonPreviewApp extends StatelessWidget {
  const StopButtonPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Stop button preview (harness)',
    debugShowCheckedModeBanner: false,
    theme: buildRemoteTheme(),
    home: const _StopButtonPreview(),
  );
}

class _StopButtonPreview extends StatefulWidget {
  const _StopButtonPreview();

  @override
  State<_StopButtonPreview> createState() => _StopButtonPreviewState();
}

class _StopButtonPreviewState extends State<_StopButtonPreview> {
  RemoteSnapshot _snapshot = const RemoteSnapshot(
    status: RemoteStatus.discovering,
  );

  void _start() {
    setState(
      () => _snapshot = const RemoteSnapshot(status: RemoteStatus.discovering),
    );
  }

  void _stop() {
    setState(() => _snapshot = const RemoteSnapshot(status: RemoteStatus.idle));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Preview harness — Stop button')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              key: const Key('preview-harness-banner'),
              width: double.infinity,
              color: colors.tertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Preview harness: discovery is simulated and nothing is sent '
                'to a TV. This is not the shipping app.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onTertiaryContainer),
              ),
            ),
            Expanded(
              child: ConnectScreen(
                snapshot: _snapshot,
                onDiscover: _start,
                onCancelDiscovery: _stop,
                onConnectHost: (String host, int? port) {},
                onConnectDevice: (DiscoveredTv tv) {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}
