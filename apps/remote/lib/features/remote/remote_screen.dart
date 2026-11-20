import 'package:material_ui/material_ui.dart';
import 'package:remote_core/remote_core.dart';

import '../../theme/remote_theme.dart';
import '../../widgets/haptics.dart';

/// The connected remote. Pure presentation: snapshot in, callbacks out.
class RemoteScreen extends StatelessWidget {
  const RemoteScreen({
    super.key,
    required this.snapshot,
    required this.onVolumeUp,
    required this.onVolumeDown,
    required this.onSetVolume,
    required this.onToggleMute,
    required this.onBeginVolumeHold,
    required this.onEndVolumeHold,
    required this.onRefreshVolume,
    required this.onPress,
    required this.onPowerOff,
  });

  final RemoteSnapshot snapshot;
  final VoidCallback onVolumeUp;
  final VoidCallback onVolumeDown;
  final void Function(int volume) onSetVolume;
  final VoidCallback onToggleMute;
  final void Function({required bool up}) onBeginVolumeHold;
  final VoidCallback onEndVolumeHold;
  final VoidCallback onRefreshVolume;
  final void Function(RemoteKey key) onPress;
  final VoidCallback onPowerOff;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final wide = constraints.maxWidth >= 840;
        final volume = _VolumePanel(
          snapshot: snapshot,
          onVolumeUp: onVolumeUp,
          onVolumeDown: onVolumeDown,
          onSetVolume: onSetVolume,
          onToggleMute: onToggleMute,
          onBeginVolumeHold: onBeginVolumeHold,
          onEndVolumeHold: onEndVolumeHold,
          onRefreshVolume: onRefreshVolume,
        );
        final navigation = _NavigationPanel(
          snapshot: snapshot,
          onPress: onPress,
        );

        return SingleChildScrollView(
          key: Key(wide ? 'remote-wide-layout' : 'remote-phone-layout'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Banner(snapshot: snapshot),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 5, child: volume),
                        const SizedBox(width: 20),
                        Expanded(flex: 5, child: navigation),
                      ],
                    )
                  else ...<Widget>[
                    volume,
                    const SizedBox(height: 20),
                    navigation,
                  ],
                  const SizedBox(height: 24),
                  _PowerButton(onPowerOff: onPowerOff),
                  const SizedBox(height: 12),
                  Text(
                    snapshot.latencyMs == null
                        ? 'Commands travel only over your local network.'
                        : 'Last command round trip: ${snapshot.latencyMs} ms '
                              '(local only, never uploaded).',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.snapshot});

  final RemoteSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (snapshot.status == RemoteStatus.asleep) {
      children.add(
        _BannerCard(
          key: const Key('reconnect-banner'),
          color: RemoteColors.warning,
          icon: Icons.sync,
          title: snapshot.reconnectAttempt == null
              ? 'TV unreachable'
              : 'Reconnecting (attempt ${snapshot.reconnectAttempt! + 1})',
          message:
              'The TV stopped answering. Reconnecting automatically; the '
              'stored key means no new prompt is needed.',
        ),
      );
    }

    if (snapshot.status == RemoteStatus.degraded) {
      children.add(
        _BannerCard(
          key: const Key('degraded-banner'),
          color: RemoteColors.warning,
          icon: Icons.speaker,
          title: 'External audio',
          message:
              'This TV reports volume as -1, so a soundbar or receiver '
              'owns the volume. Use the step buttons; the slider is off.',
        ),
      );
    }

    if (snapshot.commandError != null) {
      children.add(
        _BannerCard(
          key: const Key('command-error'),
          color: RemoteColors.danger,
          icon: Icons.error_outline,
          title: 'That did not work',
          message: snapshot.commandError!,
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox(height: 12);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final child in children) ...<Widget>[
            child,
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
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

class _VolumePanel extends StatefulWidget {
  const _VolumePanel({
    required this.snapshot,
    required this.onVolumeUp,
    required this.onVolumeDown,
    required this.onSetVolume,
    required this.onToggleMute,
    required this.onBeginVolumeHold,
    required this.onEndVolumeHold,
    required this.onRefreshVolume,
  });

  final RemoteSnapshot snapshot;
  final VoidCallback onVolumeUp;
  final VoidCallback onVolumeDown;
  final void Function(int volume) onSetVolume;
  final VoidCallback onToggleMute;
  final void Function({required bool up}) onBeginVolumeHold;
  final VoidCallback onEndVolumeHold;
  final VoidCallback onRefreshVolume;

  @override
  State<_VolumePanel> createState() => _VolumePanelState();
}

class _VolumePanelState extends State<_VolumePanel> {
  double? _dragValue;

  @override
  void didUpdateWidget(covariant _VolumePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragValue != null &&
        oldWidget.snapshot.volume != widget.snapshot.volume) {
      // A delta arrived from the TV while dragging; the drag wins until release.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = widget.snapshot;
    final reason = snapshot.capabilities.reasonFor(RemoteControl.volumeSlider);
    final sliderEnabled = snapshot.canControl && reason == null;
    final volume = snapshot.volume;
    final value = (_dragValue ?? (volume ?? 0).toDouble())
        .clamp(0.0, 100.0)
        .toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Volume', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  key: const Key('refresh-volume'),
                  tooltip: 'Refresh volume from the TV',
                  onPressed: snapshot.canControl
                      ? withHaptic(widget.onRefreshVolume)
                      : null,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton.filledTonal(
                  key: const Key('mute-button'),
                  tooltip: snapshot.muted ? 'Unmute' : 'Mute',
                  onPressed: snapshot.canControl
                      ? withHaptic(widget.onToggleMute)
                      : null,
                  icon: Icon(
                    snapshot.muted ? Icons.volume_off : Icons.volume_up,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              label: volume == null
                  ? 'Volume unknown'
                  : 'Volume ${snapshot.muted ? 'muted at ' : ''}$volume percent',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    volume == null ? '—' : '$volume',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (snapshot.muted)
                    Text(
                      'muted',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: RemoteColors.warning,
                      ),
                    )
                  else if (volume == null)
                    Text(
                      'not reported',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Slider(
              key: const Key('volume-slider'),
              value: value,
              max: 100,
              divisions: 100,
              label: '${value.round()}',
              onChanged: sliderEnabled
                  ? (double next) => setState(() => _dragValue = next)
                  : null,
              onChangeEnd: sliderEnabled
                  ? (double next) {
                      setState(() => _dragValue = null);
                      widget.onSetVolume(next.round());
                    }
                  : null,
            ),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  reason,
                  key: const Key('volume-disabled-reason'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: RemoteColors.warning,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: _HoldButton(
                    buttonKey: const Key('volume-down'),
                    icon: Icons.remove,
                    label: 'Volume down',
                    enabled: snapshot.canControl,
                    onStep: widget.onVolumeDown,
                    onHoldStart: () => widget.onBeginVolumeHold(up: false),
                    onHoldEnd: widget.onEndVolumeHold,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _HoldButton(
                    buttonKey: const Key('volume-up'),
                    icon: Icons.add,
                    label: 'Volume up',
                    enabled: snapshot.canControl,
                    onStep: widget.onVolumeUp,
                    onHoldStart: () => widget.onBeginVolumeHold(up: true),
                    onHoldEnd: widget.onEndVolumeHold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldButton extends StatelessWidget {
  const _HoldButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onStep,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onStep;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      hint: 'Press and hold for repeats',
      child: GestureDetector(
        onLongPressStart: enabled ? (_) => onHoldStart() : null,
        onLongPressEnd: enabled ? (_) => onHoldEnd() : null,
        onLongPressCancel: enabled ? onHoldEnd : null,
        child: SizedBox(
          height: 72,
          child: OutlinedButton(
            key: buttonKey,
            onPressed: enabled ? withHaptic(onStep) : null,
            child: Icon(icon, size: 30),
          ),
        ),
      ),
    );
  }
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({required this.snapshot, required this.onPress});

  final RemoteSnapshot snapshot;
  final void Function(RemoteKey key) onPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = snapshot.capabilities.reasonFor(RemoteControl.navigation);
    final enabled = snapshot.canControl && reason == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Navigation', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'D-pad, OK, Back and Home are sent over the TV’s pointer '
              'channel.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: <Widget>[
                  _PadKey(
                    buttonKey: const Key('dpad-up'),
                    label: 'D-pad up',
                    icon: Icons.keyboard_arrow_up,
                    enabled: enabled,
                    onTap: () => onPress(RemoteKey.up),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _PadKey(
                        buttonKey: const Key('dpad-left'),
                        label: 'D-pad left',
                        icon: Icons.keyboard_arrow_left,
                        enabled: enabled,
                        onTap: () => onPress(RemoteKey.left),
                      ),
                      _PadKey(
                        buttonKey: const Key('dpad-ok'),
                        label: 'OK',
                        text: 'OK',
                        enabled: enabled,
                        onTap: () => onPress(RemoteKey.ok),
                      ),
                      _PadKey(
                        buttonKey: const Key('dpad-right'),
                        label: 'D-pad right',
                        icon: Icons.keyboard_arrow_right,
                        enabled: enabled,
                        onTap: () => onPress(RemoteKey.right),
                      ),
                    ],
                  ),
                  _PadKey(
                    buttonKey: const Key('dpad-down'),
                    label: 'D-pad down',
                    icon: Icons.keyboard_arrow_down,
                    enabled: enabled,
                    onTap: () => onPress(RemoteKey.down),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _SmallKey(
                    buttonKey: const Key('back-button'),
                    label: 'Back',
                    icon: Icons.arrow_back,
                    enabled: enabled,
                    onTap: () => onPress(RemoteKey.back),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SmallKey(
                    buttonKey: const Key('home-button'),
                    label: 'Home',
                    icon: Icons.home_outlined,
                    enabled: enabled,
                    onTap: () => onPress(RemoteKey.home),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SmallKey(
                    buttonKey: const Key('info-button'),
                    label: 'Info',
                    icon: Icons.info_outline,
                    enabled: enabled,
                    onTap: () => onPress(RemoteKey.info),
                  ),
                ),
              ],
            ),
            if (reason != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                reason,
                key: const Key('navigation-disabled-reason'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: RemoteColors.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.buttonKey,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.icon,
    this.text,
  }) : assert(icon != null || text != null, 'a key needs an icon or a label');

  final Key buttonKey;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final IconData? icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Semantics(
        button: true,
        label: label,
        enabled: enabled,
        child: SizedBox(
          width: 68,
          height: 68,
          child: IconButton.filledTonal(
            key: buttonKey,
            onPressed: enabled ? withHaptic(onTap) : null,
            icon: icon == null
                ? Text(
                    text!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  )
                : Icon(icon, size: 30),
          ),
        ),
      ),
    );
  }
}

class _SmallKey extends StatelessWidget {
  const _SmallKey({
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        key: buttonKey,
        onPressed: enabled ? withHaptic(onTap) : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 20),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.onPowerOff});

  final VoidCallback onPowerOff;

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('power-confirm-dialog'),
        title: const Text('Turn off the TV?'),
        content: const Text(
          'The TV will switch off and this remote will disconnect until you '
          'connect again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('power-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (confirmed == true) onPowerOff();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        key: const Key('power-button'),
        onPressed: withHaptic(() => _confirm(context)),
        icon: const Icon(Icons.power_settings_new),
        label: const Text('Turn off TV'),
        style: OutlinedButton.styleFrom(
          foregroundColor: RemoteColors.danger,
          side: BorderSide(color: RemoteColors.danger.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}
