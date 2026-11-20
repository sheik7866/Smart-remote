import 'package:material_ui/material_ui.dart';
import 'package:remote_core/remote_core.dart';

import '../theme/remote_theme.dart';

/// Short, truthful connection label. Never says "connected" while the
/// controller is not accepting commands.
String statusLabel(RemoteSnapshot snapshot) {
  switch (snapshot.status) {
    case RemoteStatus.idle:
      return snapshot.hasSearched ? 'No TV found' : 'Not connected';
    case RemoteStatus.discovering:
      return 'Searching';
    case RemoteStatus.connecting:
      return 'Connecting';
    case RemoteStatus.awaitingApproval:
      return 'Approve on TV';
    case RemoteStatus.connected:
      return 'Connected';
    case RemoteStatus.degraded:
      return 'Limited';
    case RemoteStatus.error:
      return 'Error';
    case RemoteStatus.asleep:
      return snapshot.reconnectAttempt == null ? 'TV asleep' : 'Reconnecting';
  }
}

Color statusColor(RemoteSnapshot snapshot) {
  switch (snapshot.status) {
    case RemoteStatus.connected:
      return RemoteColors.good;
    case RemoteStatus.degraded:
    case RemoteStatus.awaitingApproval:
    case RemoteStatus.connecting:
    case RemoteStatus.discovering:
    case RemoteStatus.asleep:
      return RemoteColors.warning;
    case RemoteStatus.error:
      return RemoteColors.danger;
    case RemoteStatus.idle:
      return const Color(0xFF8A97A3);
  }
}

/// The chip in the app bar. Screen readers get a full sentence, not a dot.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.snapshot});

  final RemoteSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = statusLabel(snapshot);
    final color = statusColor(snapshot);

    return Semantics(
      label: 'Connection status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
