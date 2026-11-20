# lg_discovery

Native discovery helpers that a pure-Dart package cannot express.

| Call | Android | iOS | Other |
| --- | --- | --- | --- |
| `acquireMulticastLock()` / `releaseMulticastLock()` | `WifiManager.MulticastLock`, held for one SSDP sweep | no-op (iOS has no such lock) | no-op |
| `browseBonjour()` | empty (Android uses SSDP) | `NetServiceBrowser` for `_lg-mrt._tcp`, resolved to IPv4 where possible | empty |

The Dart side never throws for an unsupported platform, so the app can wire
both calls unconditionally. A native failure still surfaces as a
`PlatformException`; the sweep hook in `remote_core` treats that as best-effort
and manual IP entry remains available.

## Why two mechanisms

* **Android** drops multicast packets for apps without a `MulticastLock`, which
  makes SSDP discovery look broken even on a healthy network. The lock is
  acquired immediately before the sweep and released in a `finally`.
* **iOS** gates raw multicast behind `com.apple.developer.networking.multicast`,
  which needs Apple's approval. Bonjour browsing needs no entitlement and uses
  the `_lg-mrt._tcp` service LG advertises, so it is the default path there.

## Build status

The Dart wrapper is covered by tests against a mocked `MethodChannel`
(`flutter test`). The Kotlin and Swift sources are compiled in CI by the
`android-build` and `ios-build` jobs, which also assert that
`LgDiscoveryPlugin.class` and `lg_discovery.framework` were produced. They
have **never run on a device or a real network**, so treat discovery
behaviour as unverified until a physical sweep is recorded in the QA
checklist. The Android build files follow the Flutter 3.50.1 plugin template
(AGP 9.3.1, Kotlin 2.4.20, `compileSdk 36`).

## Adding the plugin

```yaml
dependencies:
  lg_discovery:
    path: ../../plugins/lg_discovery
```

No manual registration is needed: Flutter's plugin loader registers
`LgDiscoveryPlugin` on both platforms.
