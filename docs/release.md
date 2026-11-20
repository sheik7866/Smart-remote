# Release preparation (M9)

Status: **release artefacts drafted; nothing has been submitted to a store.**
The app has not run on a physical TV, so it cannot honestly be released as
"working" yet. This document is the checklist that must be completed first.

## Version compatibility matrix

| Platform / TV | Claimed | Evidence |
| --- | --- | --- |
| Android 8 (API 26)+ | Target | Build not run in this workspace (no Android SDK) |
| iOS 14+ | Target | Build not run (requires macOS + Xcode) |
| Web (Chromium/Safari) | Limited, manual IP only | Web build compiled and rendered; limits documented in-app |
| webOS 3.0 (2016) and newer | Target | Mock-tested only |
| Secure-only sets (`wss://:3001`, ~2022+) | Expected to work | Mock `wss` profile; no hardware |
| Sets exposing only plain `ws://:3000` | Expected to work | Mock plain profile; no hardware |
| ARC/eARC soundbar volume | Step commands only, slider disabled | Mock ARC profile; no hardware |

"Mock-tested" means the protocol exchange and the UI state are covered by
automated tests against `tools/mock_tv`. It is not evidence about a real TV.
Only signed rows in [qa-physical-tv-checklist.md](qa-physical-tv-checklist.md)
count.

## Store metadata (draft)

**Name:** Smart Remote — LG TV

**Short description:** A fast, private remote for LG webOS TVs on your Wi-Fi.

**Full description:**

> Control your LG webOS television from your phone, over your own network.
> Pair once with the prompt on the TV, then use volume, mute, D-pad, OK, Back,
> Home and power off. Nothing is routed through a cloud service, and the
> pairing key never leaves your device keystore.
>
> Smart Remote adapts to the TV it finds: controls that a set does not support
> are disabled with an explanation instead of failing silently. When a soundbar
> owns the volume (ARC/eARC), the app explains why the slider is unavailable
> and keeps the step buttons.
>
> Requires the TV and the phone on the same local network.

**Keywords:** LG TV remote, webOS, smart remote, local, private, Wi-Fi remote

**Category:** Utilities

## Privacy policy (draft, publish as a hosted page before submission)

Smart Remote does not collect analytics, advertising identifiers or location.
It has no account system and no cloud relay.

* **Network:** the app talks only to the TV address you choose, over your local
  network. It sends SSDP discovery datagrams to `239.255.255.250:1900`.
* **Pairing key:** stored in iOS Keychain / Android Keystore-backed storage,
  marked this-device-only and non-synchronisable. It is never transmitted to a
  server and never written to logs.
* **Diagnostics:** command latency is measured locally and only displayed; it
  is never uploaded. There is no telemetry endpoint in the app.
* **Crash reporting:** not enabled in this build. If added, it must be opt-in,
  must redact keys and network addresses, and must be described here before
  release.
* **Children:** no data is collected from anyone, including children.

Contact: the repository owner (add a monitored address before publishing).

## Crash reporting plan (not implemented)

When it is added:

* opt-in only, with a clear explanation;
* no screenshots, no keystrokes, no client key, no IP or MAC;
* scrub the credential store namespace and any `client-key` field before upload;
* a unit test must assert the redaction, mirroring `SsapLogger.redact`.

## Release checklist

- [ ] All rows in the physical TV checklist filled and signed for at least three
      sets (older webOS, newer webOS, ARC soundbar).
- [ ] M8 either signed off or explicitly dropped from the release notes.
- [ ] iOS multicast entitlement requested, or discovery documented as
      Bonjour/manual-only on iOS.
- [ ] Android multicast lock implemented and verified on a 2.4 GHz and a 5 GHz
      network.
- [ ] Signing keys created and stored outside the repository.
- [ ] `LICENSE` chosen and committed (currently unset).
- [ ] Version bumped from `0.1.0+1`, build number incremented.
- [ ] Privacy policy hosted at a public URL and linked from both stores.
- [ ] Export-compliance answer for encryption (standard TLS only).
- [ ] Store screenshots captured on a phone and a tablet, dark theme.
- [ ] Release notes state what is supported on web and what is not.
- [ ] A final `flutter build apk` / `flutter build ipa` on the release machines.

## Known gaps at the time of writing

1. No physical TV has been tested. This is the blocking item.
2. iOS multicast entitlement and Bonjour browsing are not implemented; only
   manual IP works on iOS today.
3. Android multicast lock is not implemented; SSDP may miss replies on some
   devices, so manual entry is the fallback.
4. No crash reporting, no analytics, no accounts: deliberate, not omissions.
5. Web is a limited manual-IP client; the bridge was evaluated and not shipped.
