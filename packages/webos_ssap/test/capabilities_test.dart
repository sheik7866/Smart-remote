import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

import 'support.dart';

void main() {
  test('probes absolute volume and pointer support', () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);

    final capabilities = await CapabilityProbe(SsapClient(session: session)).probe();

    expect(capabilities.probed, isTrue);
    expect(capabilities.absoluteVolume, CapabilitySupport.supported);
    expect(capabilities.hasAbsoluteVolume, isTrue);
    expect(capabilities.mute, CapabilitySupport.supported);
    expect(capabilities.pointer, CapabilitySupport.supported);
    expect(capabilities.externalAudio, isFalse);
  });

  test('ARC report marks absolute volume unsupported, not unknown', () async {
    final tv = await startTv(MockTvConfig(volume: VolumeMode.arcExternal));
    final session = await paired(tv);

    final capabilities = await CapabilityProbe(SsapClient(session: session)).probe();

    expect(capabilities.absoluteVolume, CapabilitySupport.unsupported);
    expect(capabilities.externalAudio, isTrue);
  });

  test('a denied probe leaves capabilities unknown instead of throwing',
      () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);
    tv.denyPermissions = true;

    final capabilities = await CapabilityProbe(SsapClient(session: session)).probe();

    expect(capabilities.probed, isFalse);
    expect(capabilities.absoluteVolume, CapabilitySupport.unknown);
    expect(capabilities.pointer, CapabilitySupport.unknown);
  });
}
