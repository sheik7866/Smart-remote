import 'package:material_ui/material_ui.dart';

import '../../theme/remote_theme.dart';

/// The browser limitations, stated plainly. This screen exists so the web
/// build never has to pretend it can do what a native client can.
class LimitationsScreen extends StatelessWidget {
  const LimitationsScreen({super.key});

  static const List<({String title, String body})>
  limits = <({String title, String body})>[
    (
      title: 'No automatic discovery',
      body:
          'Browsers cannot send UDP multicast, so SSDP cannot find a TV. '
          'Enter the TV address by hand.',
    ),
    (
      title: 'No self-signed certificates',
      body:
          'LG TVs serve wss://:3001 with a self-signed certificate. Browsers '
          'refuse it, and there is no way for a page to accept it.',
    ),
    (
      title: 'Mixed content blocks ws://',
      body:
          'A page served over https:// cannot open a plain ws:// connection '
          'to the TV. Only a page served over http:// on the same LAN can use '
          'plain WebSockets.',
    ),
    (
      title: 'No persistent key',
      body:
          'A pairing key is kept in memory for this tab only. Browsers have '
          'no Keychain or Keystore, and storing a key in localStorage would be '
          'a downgrade, not a feature.',
    ),
    (
      title: 'No background reconnect',
      body:
          'Closing the tab ends the session. There is no background service '
          'to reconnect when the TV wakes up.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Browser limitations')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: RemoteColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: RemoteColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'The native Android and iOS apps are the supported way to '
                    'control a TV. This web build is a documented, limited '
                    'client, not a feature-equivalent one.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 20),
                for (final limit in limits) ...<Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(limit.title, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            limit.body,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
                Text(
                  'Local bridge: evaluated and deliberately not shipped. It '
                  'would hold keys in the host keystore and serve the web '
                  'client over loopback, which is a separate product with its '
                  'own security review.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
