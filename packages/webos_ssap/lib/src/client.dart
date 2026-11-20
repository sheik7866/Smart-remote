import 'errors.dart';
import 'session.dart';

/// Volume state as reported by the TV.
class VolumeState {
  const VolumeState({required this.volume, required this.muted});

  /// LG reports `-1` when volume is controlled by an external device (ARC /
  /// eARC soundbar). Absolute `setVolume` is meaningless in that case.
  final int volume;
  final bool muted;

  bool get absoluteVolumeSupported => volume >= 0;

  @override
  String toString() => 'VolumeState(volume: $volume, muted: $muted)';
}

/// Typed command surface over an [SsapSession].
///
/// URIs are kept in one place so the UI never sees protocol strings, and so QA
/// can map every button to an exact request.
class SsapClient {
  SsapClient({required this.session});

  final SsapSession session;

  static const String volumeUpUri = 'ssap://audio/volumeUp';
  static const String volumeDownUri = 'ssap://audio/volumeDown';
  static const String setVolumeUri = 'ssap://audio/setVolume';
  static const String setMuteUri = 'ssap://audio/setMute';
  static const String getVolumeUri = 'ssap://audio/getVolume';
  static const String turnOffUri = 'ssap://system/turnOff';
  static const String channelUpUri = 'ssap://tv/channelUp';
  static const String channelDownUri = 'ssap://tv/channelDown';
  static const String playUri = 'ssap://media.controls/play';
  static const String pauseUri = 'ssap://media.controls/pause';
  static const String stopUri = 'ssap://media.controls/stop';
  static const String launchAppUri = 'ssap://system.launcher/launch';
  static const String serviceListUri = 'ssap://api/getServiceList';
  static const String pointerSocketUri =
      'ssap://com.webos.service.networkinput/getPointerInputSocket';

  Future<void> volumeUp() => _command(volumeUpUri);

  Future<void> volumeDown() => _command(volumeDownUri);

  Future<void> setVolume(int volume) => _command(
        setVolumeUri,
        payload: <String, dynamic>{'volume': volume.clamp(0, 100)},
      );

  Future<void> setMute(bool mute) => _command(
        setMuteUri,
        payload: <String, dynamic>{'mute': mute},
      );

  Future<void> turnOff() => _command(turnOffUri);

  Future<void> channelUp() => _command(channelUpUri);

  Future<void> channelDown() => _command(channelDownUri);

  Future<void> play() => _command(playUri);

  Future<void> pause() => _command(pauseUri);

  Future<void> stop() => _command(stopUri);

  Future<void> launchApp(String appId) => _command(
        launchAppUri,
        payload: <String, dynamic>{'id': appId},
      );

  Future<VolumeState> getVolume() async {
    final payload = await session.request(getVolumeUri);
    return _parseVolume(payload);
  }

  Future<SsapSubscription> subscribeVolume() => session.subscribe(getVolumeUri);

  /// Parses both the flat shape (`volume`, `muted`) and the nested
  /// `volumeStatus` shape seen on some firmwares.
  VolumeState _parseVolume(Map<String, dynamic> payload) {
    final nested = payload['volumeStatus'];
    final volume = payload['volume'] ??
        (nested is Map<String, dynamic> ? nested['volume'] : null);
    final muted = payload['muted'] ??
        payload['muteStatus'] ??
        (nested is Map<String, dynamic> ? nested['muteStatus'] : null);
    return VolumeState(
      volume: volume is num ? volume.toInt() : -1,
      muted: muted == true,
    );
  }

  Future<List<String>> serviceList() async {
    final payload = await session.request(serviceListUri);
    final services = payload['services'];
    if (services is! List<dynamic>) return const <String>[];
    return <String>[
      for (final service in services)
        if (service is Map<String, dynamic> && service['name'] is String)
          service['name'] as String,
    ];
  }

  Future<Map<String, dynamic>> requestPointerSocket() =>
      session.request(pointerSocketUri);

  Future<void> _command(
    String uri, {
    Map<String, dynamic>? payload,
  }) async {
    final response = await session.request(uri, payload: payload);
    if (response['returnValue'] == false) {
      throw SsapError(
        SsapErrorKind.capability,
        'tv_rejected',
        (response['errorText'] ?? 'The TV rejected that command.').toString(),
        uri: uri,
      );
    }
  }
}
