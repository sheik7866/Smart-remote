# Setup

Status: M3–M7 implemented in code; M8 schema only; M9 artefacts drafted. Platform configuration is **declared but not device-verified**: no Android or iOS build has been produced in this workspace, and no physical TV has been tested. Anything unverified is marked as such below.

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

### Desktop toolchain and browser

The sandbox has no root, so the Linux desktop toolchain and a browser are installed user-locally:

| Component | Location | Notes |
| --- | --- | --- |
| clang/clang++, cmake, ninja, pkg-config, GTK 3, X/NSS libs | `~/.local/envs/dev` (conda-forge via micromamba) | keep `glib` at 2.88: 2.90 ships without `glibconfig.h`, which breaks GTK's CMake detection |
| Chrome for Testing 158 | `~/.local/chrome/chrome-linux64/chrome` | accepted by `flutter doctor`; usable for headless checks |
| Flutter 3.50.0 | `~/.local/flutter` | bundled Dart 3.14.0 |
| Dart 3.14.1 | `~/.local/dart-sdk` | tests and protocol package |

```bash
# everything needed for a desktop build and Chrome-assisted checks
export PATH="$HOME/.local/envs/dev/bin:$HOME/.local/flutter/bin:$PATH"
export PKG_CONFIG_PATH="$HOME/.local/envs/dev/lib/pkgconfig:$HOME/.local/envs/dev/share/pkgconfig"
export LD_LIBRARY_PATH="$HOME/.local/envs/dev/lib"
export CMAKE_PREFIX_PATH="$HOME/.local/envs/dev"
export CHROME_EXECUTABLE="$HOME/.local/chrome/chrome-linux64/chrome"
```

With that environment `flutter doctor` reports Flutter, Chrome and the Linux toolchain green (only `eglinfo` is missing, which is a warning). `flutter build linux --debug` produces `build/linux/x64/debug/bundle/smart_remote`. The VM has no display server, so the desktop binary builds but cannot be launched here; the web build is the runnable preview target.

M2 added `flutter_secure_storage` for Keychain/Keystore, which also pulls a Linux `libsecret` backend (`libsecret-1` >= 0.18.4, via pkg-config) and its `jni` FFI plugin into desktop builds. The Linux desktop build has **not** been re-verified since that dependency landed; it is a development convenience, and iOS/Android/web are unaffected. If desktop builds are wanted, add `libsecret` (conda-forge has 0.21.8) plus whatever `jni` needs for CMake and re-run `flutter build linux --debug`.

Rebuild the conda environment if `~/.local` is lost:

```bash
curl -fsSL -o ~/.local/bin/micromamba \
  https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-linux-64
chmod +x ~/.local/bin/micromamba
~/.local/bin/micromamba create -y -p ~/.local/envs/dev -c conda-forge \
  clang clangxx cmake ninja pkg-config gtk3 nss nspr alsa-lib at-spi2-core \
  xorg-libxcomposite xorg-libxdamage xorg-libxfixes xorg-libxrandr xz zlib \
  expat freetype fontconfig libpng pixman libffi pcre2 harfbuzz bzip2 'glib=2.88'
```

## Bootstrap

```bash
# Protocol core + mock TV (works today, no Flutter needed)
cd tools/mock_tv && dart pub get && dart test
cd ../../packages/webos_ssap && dart pub get && dart analyze && dart test
cd ../../packages/remote_core && dart pub get && dart analyze && dart test

# The accounts schema guard (test/schema_test.dart) runs inside that suite.

# Manual development against a scripted TV
dart run tools/mock_tv --port 3000            # plain ws
dart run tools/mock_tv --pairing deny         # denial path
dart run tools/mock_tv --volume arc           # ARC volume -1 profile

# Flutter app shell (apps/remote)
cd apps/remote && flutter pub get && flutter analyze && flutter test
flutter run -d chrome   # web; Android/iOS need their platform toolchains
```

## Platform configuration *(declared, not device-verified)*

### iOS

* `Info.plist`: `NSLocalNetworkUsageDescription` explaining that the app talks to the TV on the local network.
* `NSBonjourServices`: `_lg-mrt._tcp`.
* Entitlement `com.apple.developer.networking.multicast` for raw SSDP — request approval from Apple; the Bonjour path works without it.
* Pairing keys: Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false` so keys never sync to iCloud.

Declared in `ios/Runner/Info.plist`: `NSLocalNetworkUsageDescription` and
`NSBonjourServices` (`_lg-mrt._tcp`). Bonjour browsing is implemented in
`plugins/lg_discovery` (`NetServiceBrowser`, resolved to IPv4). The multicast
entitlement is **not** added, because it needs Apple's approval and adding it
would break signing without a matching profile; Bonjour is therefore the iOS
discovery path. The Swift plugin has not been compiled here (no Xcode).

### Android

* `AndroidManifest.xml`: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`; `NEARBY_WIFI_DEVICES` on API 33+.
* Enable a multicast lock for the duration of a discovery sweep, then release it.
* Pairing keys: Keystore-backed AES-GCM, excluded from Auto Backup (`android:allowBackup="false"` or explicit backup rules).
* Never request `QUERY_ALL_PACKAGES` or unrelated permissions.

Declared in `android/app/src/main/AndroidManifest.xml`: `INTERNET`,
`ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`,
`NEARBY_WIFI_DEVICES` (`neverForLocation`) and
`android:usesCleartextTraffic="true"` so `ws://:3000` works on Android 9+.
`plugins/lg_discovery` acquires and releases the `WifiManager.MulticastLock`
around each sweep. It has **not been compiled** here (no Android SDK), so treat
SSDP discovery as unverified until an Android build and a real-network sweep
have run; manual entry is the fallback.

### Web

* No pairing-key storage of any kind. Session memory only, or keys owned by the optional native bridge.
* The app must show the browser limitations rather than attempting to work around them silently.

## Supabase *(post-MVP, optional — schema only)*

See [sync.md](sync.md). The migration is `supabase/migrations/0001_preferences.sql`;
no project exists and no client code is wired, so accounts are off in the app.

* Only for accounts and sync of device nicknames and UI preferences.
* Row Level Security on every table; keys at rest only inside the device keystore.
* Any schema change that could hold a secret, client key, IP or MAC must be rejected in review.
