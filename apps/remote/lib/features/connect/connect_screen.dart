import 'package:material_ui/material_ui.dart';
import 'package:remote_core/remote_core.dart';

import '../../theme/remote_theme.dart';
import '../../widgets/haptics.dart';

/// The no-TV experience: discovery, manual entry and every pairing state.
///
/// Pure presentation: it receives a snapshot and callbacks, so it can be tested
/// without a controller, sockets or a TV.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.snapshot,
    required this.onDiscover,
    required this.onConnectHost,
    required this.onConnectDevice,
    this.onStopWaiting,
    this.discoverySupported = true,
    this.discoveryUnsupportedReason,
    this.webLimitations = false,
  });

  final RemoteSnapshot snapshot;
  final VoidCallback onDiscover;
  final void Function(String host, int? port) onConnectHost;
  final void Function(DiscoveredTv tv) onConnectDevice;
  final VoidCallback? onStopWaiting;
  final bool discoverySupported;
  final String? discoveryUnsupportedReason;
  final bool webLimitations;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController();
  String? _formError;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _submitManual() {
    final host = _host.text.trim();
    if (host.isEmpty) {
      setState(() => _formError = 'Enter the TV IP address first.');
      return;
    }
    final portText = _port.text.trim();
    int? port;
    if (portText.isNotEmpty) {
      port = int.tryParse(portText);
      if (port == null || port < 1 || port > 65535) {
        setState(
          () => _formError = 'The port must be a number from 1 to 65535.',
        );
        return;
      }
    }
    setState(() => _formError = null);
    widget.onConnectHost(host, port);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final wide = constraints.maxWidth >= 900;
        final hero = _Hero(snapshot: widget.snapshot);
        final actions = _buildActions(context);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 5, child: hero),
                        const SizedBox(width: 48),
                        Expanded(flex: 6, child: actions),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        hero,
                        const SizedBox(height: 32),
                        actions,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions(BuildContext context) {
    final snapshot = widget.snapshot;
    final busy = snapshot.isBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.webLimitations) ...<Widget>[
          const _WebBanner(),
          const SizedBox(height: 16),
        ],
        if (snapshot.error != null) ...<Widget>[
          _MessageCard(
            key: const Key('connection-error'),
            icon: Icons.error_outline,
            color: RemoteColors.danger,
            title: 'What happened',
            message: snapshot.error!,
          ),
          const SizedBox(height: 16),
        ],
        if (snapshot.status == RemoteStatus.awaitingApproval) ...<Widget>[
          const _WaitingCard(),
          const SizedBox(height: 12),
          if (widget.onStopWaiting != null)
            OutlinedButton(
              onPressed: withHaptic(widget.onStopWaiting!),
              child: const Text('Stop waiting'),
            ),
          const SizedBox(height: 16),
        ],
        if (!widget.discoverySupported)
          _MessageCard(
            icon: Icons.wifi_off,
            color: RemoteColors.warning,
            title: 'Automatic discovery unavailable',
            message:
                widget.discoveryUnsupportedReason ??
                'This platform cannot search the network.',
          )
        else
          FilledButton.icon(
            key: const Key('find-tv-button'),
            onPressed: busy ? null : withHaptic(widget.onDiscover),
            icon: snapshot.status == RemoteStatus.discovering
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(
              snapshot.status == RemoteStatus.discovering
                  ? 'Searching…'
                  : 'Find my TV',
            ),
          ),
        const SizedBox(height: 20),
        if (snapshot.discovered.isNotEmpty) ...<Widget>[
          Text(
            'Found on this network',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                for (final tv in snapshot.discovered)
                  ListTile(
                    leading: const Icon(Icons.tv),
                    title: Text(tv.displayName),
                    subtitle: Text(
                      tv.source == DiscoverySource.subnetProbe
                          ? '${tv.host} — found by network scan, confirm it '
                                'is your TV'
                          : tv.host,
                    ),
                    trailing: TextButton(
                      onPressed: busy
                          ? null
                          : withHaptic(() => widget.onConnectDevice(tv)),
                      child: const Text('Connect'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Enter the TV address',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Always available, even when discovery is blocked by the '
                  'network.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('manual-host-field'),
                  controller: _host,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'TV IP address',
                    hintText: '192.168.1.20',
                    prefixIcon: Icon(Icons.lan),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 130,
                      child: TextField(
                        key: const Key('manual-port-field'),
                        controller: _port,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submitManual(),
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          hintText: 'optional',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonal(
                        key: const Key('manual-connect-button'),
                        onPressed: busy ? null : withHaptic(_submitManual),
                        child: const Text('Connect'),
                      ),
                    ),
                  ],
                ),
                if (_formError != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _formError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Your pairing key stays on this device. It is never sent to a server '
          'or written to logs.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.snapshot});

  final RemoteSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presentation = _heroCopy(snapshot);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const SizedBox(height: 12),
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Icon(
            presentation.icon,
            size: 56,
            color: presentation.warning
                ? RemoteColors.warning
                : theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          presentation.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          presentation.body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (snapshot.status == RemoteStatus.awaitingApproval ||
            snapshot.status == RemoteStatus.connecting) ...<Widget>[
          const SizedBox(height: 20),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ],
      ],
    );
  }
}

typedef _HeroPresentation = ({
  String title,
  String body,
  IconData icon,
  bool warning,
});

_HeroPresentation _heroCopy(RemoteSnapshot snapshot) {
  switch (snapshot.status) {
    case RemoteStatus.discovering:
      return (
        title: 'Looking for your TV',
        body:
            'Searching this network for LG webOS televisions. '
            'This takes a few seconds.',
        icon: Icons.wifi_tethering,
        warning: false,
      );
    case RemoteStatus.connecting:
      return (
        title: 'Connecting',
        body:
            'Trying the secure port first, then plain. A stored key is '
            'reused silently when the TV still knows this remote.',
        icon: Icons.sync,
        warning: false,
      );
    case RemoteStatus.awaitingApproval:
      return (
        title: 'Approve on your TV',
        body:
            'Look at the TV and accept the pairing request for '
            '"Smart Remote". The prompt expires after about a minute.',
        icon: Icons.verified_user_outlined,
        warning: true,
      );
    case RemoteStatus.error:
      return (
        title: 'Could not connect',
        body:
            'The TV did not complete the connection. The reason is below, '
            'with the address you can retry.',
        icon: Icons.error_outline,
        warning: true,
      );
    case RemoteStatus.connected:
    case RemoteStatus.degraded:
      return (
        title: 'Connected',
        body: 'The remote is ready.',
        icon: Icons.check_circle_outline,
        warning: false,
      );
    case RemoteStatus.asleep:
      return (
        title: 'TV asleep',
        body: 'The TV stopped answering. It may be in standby.',
        icon: Icons.bedtime_outlined,
        warning: true,
      );
    case RemoteStatus.idle:
      if (snapshot.hasSearched && snapshot.discovered.isNotEmpty) {
        return (
          title: 'Choose your TV',
          body: 'Tap the television you want to control.',
          icon: Icons.tv,
          warning: false,
        );
      }
      if (snapshot.hasSearched) {
        return (
          title: 'No TVs found',
          body: 'Check the network, then try the address by hand.',
          icon: Icons.tv_off,
          warning: true,
        );
      }
      return (
        title: 'No TV connected',
        body:
            'Pair an LG webOS TV on your Wi-Fi. Everything stays on your '
            'local network.',
        icon: Icons.settings_remote,
        warning: false,
      );
  }
}

class _WebBanner extends StatelessWidget {
  const _WebBanner();

  @override
  Widget build(BuildContext context) {
    return _MessageCard(
      key: const Key('web-limits-banner'),
      icon: Icons.public_off,
      color: RemoteColors.warning,
      title: 'Browser limits',
      message:
          'No automatic discovery, no self-signed certificates, and no '
          'persistent key storage. See “Browser limitations” in the menu.',
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard();

  @override
  Widget build(BuildContext context) {
    return _MessageCard(
      icon: Icons.tv,
      color: RemoteColors.warning,
      title: 'Waiting for the TV',
      message:
          'Accept the prompt on the TV. Nothing is stored until the TV '
          'confirms.',
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
