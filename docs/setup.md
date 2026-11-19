# Setup

Status: architecture phase. These are the planned toolchain and entitlements; commands marked *(planned)* land with the milestone that introduces the code.

## Toolchain

| Tool | Version | Needed for |
| --- | --- | --- |
| Flutter | 3.24+ (stable, Dart 3.5+) | app, iOS, Android, web |
| Xcode | 15+ on macOS | iOS build, signing, Keychain, multicast entitlement |
| Android Studio / SDK | SDK 34, Build Tools 34 | Android build, Keystore, multicast lock |
| Dart SDK | bundled with Flutter | `packages/webos_ssap` tests |

**Environment facts for this workspace:** the cloud VM has Node 26 and Bun 1.4.4 but **no Flutter or Dart SDK**, and it is Linux, so **iOS cannot be built or run here** — that requires a Mac with Xcode. The protocol package and mock TV can be developed and tested with a standalone Dart SDK on Linux once installed; the Flutter app needs a Flutter SDK install (Linux desktop/Android) or a developer machine.

No Git remote is configured in this workspace, so PRs and the "complete GitHub repository" cannot be published from here yet.

### Installed in this workspace

Dart 3.14.1 (stable) is installed user-locally as `~/.local/dart-sdk`; it is not part of the repository and does not survive a rebuilt sandbox. Reinstall with the stable Linux x64 archive from `storage.googleapis.com/dart-archive`.

```bash
export PATH="$HOME/.local/dart-sdk/bin:$PATH"
```

Flutter 3.50.0 (stable, bundled Dart 3.14.0) is installed at `~/.local/flutter`, also outside the repository and not preserved by a sandbox rebuild. It can build and test the app and the web target on Linux; iOS still requires macOS with Xcode, and Android builds need the Android SDK/NDK.

```bash
export PATH="$HOME/.local/flutter/bin:$PATH"
```

## Bootstrap

```bash
# Protocol core + mock TV (works today, no Flutter needed)
cd tools/mock_tv && dart pub get && dart test
cd ../../packages/webos_ssap && dart pub get && dart analyze && dart test

# Manual development against a scripted TV
dart run tools/mock_tv --port 3000            # plain ws
dart run tools/mock_tv --pairing deny         # denial path
dart run tools/mock_tv --volume arc           # ARC volume -1 profile

# Flutter app shell (apps/remote)
cd apps/remote && flutter pub get && flutter analyze && flutter test
flutter run -d chrome   # web; Android/iOS need their platform toolchains
```

## Platform configuration *(planned)*

### iOS

* `Info.plist`: `NSLocalNetworkUsageDescription` explaining that the app talks to the TV on the local network.
* `NSBonjourServices`: `_lg-mrt._tcp`.
* Entitlement `com.apple.developer.networking.multicast` for raw SSDP — request approval from Apple; the Bonjour path works without it.
* Pairing keys: Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false` so keys never sync to iCloud.

### Android

* `AndroidManifest.xml`: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`; `NEARBY_WIFI_DEVICES` on API 33+.
* Enable a multicast lock for the duration of a discovery sweep, then release it.
* Pairing keys: Keystore-backed AES-GCM, excluded from Auto Backup (`android:allowBackup="false"` or explicit backup rules).
* Never request `QUERY_ALL_PACKAGES` or unrelated permissions.

### Web

* No pairing-key storage of any kind. Session memory only, or keys owned by the optional native bridge.
* The app must show the browser limitations rather than attempting to work around them silently.

## Supabase *(post-MVP, optional)*

* Only for accounts and sync of device nicknames and UI preferences.
* Row Level Security on every table; keys at rest only inside the device keystore.
* Any schema change that could hold a secret, client key, IP or MAC must be rejected in review.
