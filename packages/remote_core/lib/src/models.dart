import 'package:webos_ssap/webos_ssap.dart'
    show CapabilitySupport, TvCapabilities;

/// High-level connection state shown to the user.
///
/// [asleep] and [error] are deliberately distinct: a TV that stopped answering
/// after working is usually in standby, not misconfigured, and the copy differs.
enum RemoteStatus {
  /// No TV selected yet.
  idle,

  /// A discovery sweep is running.
  discovering,

  /// Opening the socket and restoring the stored key.
  connecting,

  /// The TV is showing (or about to show) its pairing prompt.
  awaitingApproval,

  /// Paired, probed and accepting commands.
  connected,

  /// Connected but with a documented limitation (for example ARC volume).
  degraded,

  /// A failure the user has to act on.
  error,

  /// The TV stopped responding and a reconnect is being attempted.
  asleep,
}

/// How a device was found, so weak evidence can be labelled in the UI.
enum DiscoverySource { ssdp, bonjour, subnetProbe }

/// A TV found on the LAN, or entered manually.
class DiscoveredTv {
  const DiscoveredTv({
    required this.host,
    this.name,
    this.modelName,
    this.location,
    this.source,
  });

  final String host;
  final String? name;
  final String? modelName;

  /// UPnP description URL, when discovery supplied one.
  final String? location;

  /// How the device was found; null when the caller did not say.
  final DiscoverySource? source;

  String get displayName {
    final value = name?.trim();
    if (value != null && value.isNotEmpty) return value;
    final model = modelName?.trim();
    if (model != null && model.isNotEmpty) return model;
    return host;
  }

  @override
  bool operator ==(Object other) => other is DiscoveredTv && other.host == host;

  @override
  int get hashCode => host.hashCode;

  @override
  String toString() => 'DiscoveredTv($displayName @ $host)';
}

/// The TV the app is talking to (or trying to).
class TvDevice {
  const TvDevice({
    required this.host,
    this.port,
    this.secure,
    this.name,
    this.modelName,
  });

  final String host;
  final int? port;
  final bool? secure;
  final String? name;
  final String? modelName;

  String get displayName {
    final value = name?.trim();
    if (value != null && value.isNotEmpty) return value;
    final model = modelName?.trim();
    if (model != null && model.isNotEmpty) return model;
    return host;
  }

  @override
  bool operator ==(Object other) =>
      other is TvDevice &&
      other.host == host &&
      other.port == port &&
      other.secure == secure;

  @override
  int get hashCode => Object.hash(host, port, secure);

  @override
  String toString() => 'TvDevice($displayName @ $host)';
}

/// The controls the UI can gate. One enum member per disabled reason, so a
/// button can always explain itself.
enum RemoteControl { volumeSlider, mute, navigation, power, apps, channel }

/// App-facing capability model.
///
/// Unknown is not unsupported: a probe that has not run yet must not claim a
/// TV cannot do something. It only means the control is not confirmed, which
/// the UI states honestly.
class RemoteCapabilities {
  const RemoteCapabilities({
    this.absoluteVolume = false,
    this.absoluteVolumeKnown = false,
    this.mute = false,
    this.muteKnown = false,
    this.navigation = false,
    this.navigationKnown = false,
    this.channel = false,
    this.mediaTransport = false,
    this.externalAudio = false,
    this.probed = false,
  });

  final bool absoluteVolume;
  final bool absoluteVolumeKnown;
  final bool mute;
  final bool muteKnown;
  final bool navigation;
  final bool navigationKnown;
  final bool channel;
  final bool mediaTransport;

  /// The TV reports volume `-1`: an ARC/eARC device owns the volume.
  final bool externalAudio;
  final bool probed;

  factory RemoteCapabilities.fromTv(TvCapabilities capabilities) {
    bool supported(CapabilitySupport value) =>
        value == CapabilitySupport.supported;
    return RemoteCapabilities(
      absoluteVolume: supported(capabilities.absoluteVolume),
      absoluteVolumeKnown:
          capabilities.absoluteVolume != CapabilitySupport.unknown,
      mute: supported(capabilities.mute),
      muteKnown: capabilities.mute != CapabilitySupport.unknown,
      navigation: supported(capabilities.pointer),
      navigationKnown: capabilities.pointer != CapabilitySupport.unknown,
      channel: supported(capabilities.channel),
      mediaTransport: supported(capabilities.mediaTransport),
      externalAudio: capabilities.externalAudio,
      probed: capabilities.probed,
    );
  }

  bool get canSetVolume => absoluteVolume;

  bool get canToggleMute => !muteKnown || mute;

  /// A visible, honest explanation for every disabled control.
  String? reasonFor(RemoteControl control) {
    switch (control) {
      case RemoteControl.volumeSlider:
        if (absoluteVolume) return null;
        if (externalAudio) {
          return 'Volume is handled by your soundbar or receiver. Use the '
              'step buttons.';
        }
        if (!absoluteVolumeKnown) {
          return 'This TV has not confirmed absolute volume, so the slider is '
              'off. The step buttons still work.';
        }
        return 'This TV does not support setting an exact volume.';
      case RemoteControl.mute:
        if (canToggleMute) return null;
        return 'This TV did not report mute support.';
      case RemoteControl.navigation:
        if (!navigationKnown) {
          return 'Navigation is not confirmed on this TV yet. It is sent over '
              'a second channel and may not work on older firmware.';
        }
        if (!navigation) {
          return 'This TV does not expose its pointer input service.';
        }
        return null;
      case RemoteControl.power:
        return null;
      case RemoteControl.apps:
        return null;
      case RemoteControl.channel:
        if (!channel) return 'This TV does not report channel control.';
        return null;
    }
  }

  Map<String, bool> get asFlags => <String, bool>{
        'absoluteVolume': absoluteVolume,
        'absoluteVolumeKnown': absoluteVolumeKnown,
        'mute': mute,
        'muteKnown': muteKnown,
        'navigation': navigation,
        'navigationKnown': navigationKnown,
        'channel': channel,
        'mediaTransport': mediaTransport,
        'externalAudio': externalAudio,
        'probed': probed,
      };

  @override
  String toString() => 'RemoteCapabilities($asFlags)';
}

/// One immutable view of the remote.
class RemoteSnapshot {
  const RemoteSnapshot({
    this.status = RemoteStatus.idle,
    this.device,
    this.volume,
    this.muted = false,
    this.capabilities = const RemoteCapabilities(),
    this.discovered = const <DiscoveredTv>[],
    this.hasSearched = false,
    this.error,
    this.commandError,
    this.latencyMs,
    this.reconnectAttempt,
    this.assembling = false,
  });

  final RemoteStatus status;
  final TvDevice? device;
  final int? volume;
  final bool muted;
  final RemoteCapabilities capabilities;
  final List<DiscoveredTv> discovered;
  final bool hasSearched;

  /// A user-actionable failure explanation (connection, discovery, pairing).
  final String? error;

  /// A one-shot command failure; does not change the connection state.
  final String? commandError;

  final int? latencyMs;

  /// Zero-based reconnect attempt, or null when not reconnecting.
  final int? reconnectAttempt;

  /// True while a command is being sent, for button-level busy states.
  final bool assembling;

  bool get isConnected =>
      status == RemoteStatus.connected || status == RemoteStatus.degraded;

  bool get canControl => isConnected;

  bool get isBusy =>
      status == RemoteStatus.discovering ||
      status == RemoteStatus.connecting ||
      status == RemoteStatus.awaitingApproval;

  bool get isReconnecting => reconnectAttempt != null;

  RemoteSnapshot copyWith({
    RemoteStatus? status,
    TvDevice? device,
    bool clearDevice = false,
    int? volume,
    bool clearVolume = false,
    bool? muted,
    RemoteCapabilities? capabilities,
    List<DiscoveredTv>? discovered,
    bool? hasSearched,
    String? error,
    bool clearError = false,
    String? commandError,
    bool clearCommandError = false,
    int? latencyMs,
    int? reconnectAttempt,
    bool clearReconnectAttempt = false,
    bool? assembling,
  }) =>
      RemoteSnapshot(
        status: status ?? this.status,
        device: clearDevice ? null : (device ?? this.device),
        volume: clearVolume ? null : (volume ?? this.volume),
        muted: muted ?? this.muted,
        capabilities: capabilities ?? this.capabilities,
        discovered: discovered ?? this.discovered,
        hasSearched: hasSearched ?? this.hasSearched,
        error: clearError ? null : (error ?? this.error),
        commandError:
            clearCommandError ? null : (commandError ?? this.commandError),
        latencyMs: latencyMs ?? this.latencyMs,
        reconnectAttempt: clearReconnectAttempt
            ? null
            : (reconnectAttempt ?? this.reconnectAttempt),
        assembling: assembling ?? this.assembling,
      );

  @override
  String toString() => 'RemoteSnapshot(${status.name}'
      '${device == null ? '' : ', ${device!.displayName}'}'
      '${error == null ? '' : ', error'}'
      '${reconnectAttempt == null ? '' : ', retry ${reconnectAttempt! + 1}'})';
}
