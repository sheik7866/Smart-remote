# Smart Remote — Flutter app

The UI for the LG webOS remote: pairing, discovery, the connected remote, and
the browser-limitations screen.

## Run

```bash
flutter pub get
flutter run -d chrome     # web preview (manual IP only)
flutter run               # Android/iOS device or emulator
```

## Test

```bash
flutter analyze
flutter test
```

## Structure

| Path | Purpose |
| --- | --- |
| `lib/app.dart` | Root widget: owns the controller, listens to snapshots, pauses reconnects in the background |
| `lib/wiring.dart` | Composition root: credential store, transport, pairing service, controller |
| `lib/features/connect` | Discovery list, manual IP entry, pairing states, errors |
| `lib/features/remote` | Volume (with hold coalescing), mute, D-pad, power off |
| `lib/features/limitations` | The five browser limitations, stated plainly |
| `lib/state/remote_actions.dart` | The callbacks the screens raise |
| `lib/storage` | Keychain/Keystore-backed credential store; memory-only on web |
| `lib/widgets` | Status chip and haptic helper |

Widgets import `remote_core` only. The protocol package (`webos_ssap`) appears
in `wiring.dart` and `storage/` and nowhere else in the UI.

## What is verified

`flutter analyze` is clean and 28 widget tests cover the connect states, manual
entry validation, capability gating, the D-pad, the power confirmation, both
responsive layouts and accessibility labels. The web build compiles and runs.

**Not verified:** no Android or iOS build has been produced, no physical TV has
been controlled, and browser behaviour against a real TV is blocked by the
TV's self-signed certificate. Nothing in this app is labelled "works on TV"
until `docs/qa-physical-tv-checklist.md` is signed.
