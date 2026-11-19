import 'client.dart';
import 'errors.dart';

enum CapabilitySupport { unknown, supported, unsupported }

/// What a specific TV has been observed to support.
///
/// Absence of evidence is [CapabilitySupport.unknown], never `unsupported` —
/// service lists differ across generations, so a missing entry proves nothing.
/// The one exception is an ARC volume report of `-1`, which is positive
/// evidence that absolute volume does not work.
class TvCapabilities {
  const TvCapabilities({
    this.absoluteVolume = CapabilitySupport.unknown,
    this.mute = CapabilitySupport.unknown,
    this.pointer = CapabilitySupport.unknown,
    this.channel = CapabilitySupport.unknown,
    this.mediaTransport = CapabilitySupport.unknown,
    this.externalAudio = false,
    this.probed = false,
  });

  final CapabilitySupport absoluteVolume;
  final CapabilitySupport mute;
  final CapabilitySupport pointer;
  final CapabilitySupport channel;
  final CapabilitySupport mediaTransport;

  /// True when the TV reports volume `-1`, i.e. an ARC/external device owns it.
  final bool externalAudio;

  /// Whether a probe has completed at least once.
  final bool probed;

  bool get hasAbsoluteVolume =>
      absoluteVolume == CapabilitySupport.supported;

  TvCapabilities copyWith({
    CapabilitySupport? absoluteVolume,
    CapabilitySupport? mute,
    CapabilitySupport? pointer,
    CapabilitySupport? channel,
    CapabilitySupport? mediaTransport,
    bool? externalAudio,
    bool? probed,
  }) =>
      TvCapabilities(
        absoluteVolume: absoluteVolume ?? this.absoluteVolume,
        mute: mute ?? this.mute,
        pointer: pointer ?? this.pointer,
        channel: channel ?? this.channel,
        mediaTransport: mediaTransport ?? this.mediaTransport,
        externalAudio: externalAudio ?? this.externalAudio,
        probed: probed ?? this.probed,
      );

  @override
  String toString() => 'TvCapabilities(absoluteVolume: ${absoluteVolume.name}, '
      'mute: ${mute.name}, pointer: ${pointer.name}, '
      'channel: ${channel.name}, mediaTransport: ${mediaTransport.name}, '
      'externalAudio: $externalAudio, probed: $probed)';
}

/// Probes a connected TV without assuming anything up front.
class CapabilityProbe {
  CapabilityProbe(this.client);

  final SsapClient client;

  Future<TvCapabilities> probe() async {
    var capabilities = const TvCapabilities();

    try {
      final volume = await client.getVolume();
      capabilities = capabilities.copyWith(
        mute: CapabilitySupport.supported,
        absoluteVolume: volume.absoluteVolumeSupported
            ? CapabilitySupport.supported
            : CapabilitySupport.unsupported,
        externalAudio: !volume.absoluteVolumeSupported,
        probed: true,
      );
    } on SsapError {
      // Volume probing can fail on some firmware; leave it unknown.
    }

    try {
      final services = await client.serviceList();
      capabilities = capabilities.copyWith(
        pointer: services.contains('com.webos.service.networkinput')
            ? CapabilitySupport.supported
            : CapabilitySupport.unknown,
        channel:
            services.contains('tv') ? CapabilitySupport.supported : CapabilitySupport.unknown,
        mediaTransport: services
                .contains('com.webos.service.mediacontroller')
            ? CapabilitySupport.supported
            : CapabilitySupport.unknown,
        probed: true,
      );
    } on SsapError {
      // A TV may deny the service list; capabilities stay unknown.
    }

    return capabilities;
  }
}
