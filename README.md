# Smart Remote — LG TV

A polished, reliable remote control for LG webOS televisions, built with Flutter for iOS and Android, plus a browser client.

> **Status: M3–M7 implemented in code; M8 schema only; M9 artefacts drafted.** `packages/webos_ssap` (60 tests), `tools/mock_tv` (2), `packages/remote_core` (40), `plugins/lg_discovery` (5) and the Flutter app (31 widget tests) are green and analyzer-clean. CI also compiles the plugin's Kotlin and Swift in Android and iOS builds. The app pairs, discovers, gates unsupported controls, reconnects and ships a limited web build — but **no behaviour has been verified on a physical LG TV**. Only signed rows in [the checklist](docs/qa-physical-tv-checklist.md) count. Architecture: [docs/architecture.md](docs/architecture.md).

## Mission

Control an LG webOS TV from a phone or a browser on the same local network: discover the TV, pair with on-screen approval, then send volume, mute, power-off and navigation commands — with honest connection status and useful errors instead of silent failure.

## Principles

1. **Local only.** Every control packet travels directly from the app to the TV over the LAN. No cloud relay, no tunnelling of control ports to the internet.
2. **Keys stay on the device.** The webOS `client-key` is written only to iOS Keychain, Android Keystore-backed storage, or a native bridge's keystore. It is never sent to Supabase or any backend, never logged, never attached to telemetry.
3. **Capabilities are discovered, not assumed.** LG webOS differs across models, firmware and audio setups (for example ARC soundbars reporting volume `-1`). The app probes and disables what a TV does not support.
4. **No unverified claims.** A command is "working" only when a row in the physical TV checklist has been signed off against a real set. CI passing proves protocol conformance, not hardware behaviour.
5. **Protocol is independent of the UI.** `packages/webos_ssap` is plain Dart with no Flutter imports; the UI consumes a typed controller API.

## Repository layout

```
packages/webos_ssap/          Dart SSAP protocol: framing, session, pairing, commands  ✅ M1–M2
 tools/mock_tv/               Mock SSAP TV server for tests and local development     ✅ M1
packages/remote_core/         State, commands, capability gating, discovery, reconnect ✅ M3–M6, ⚠️ M5 device-unverified
plugins/lg_discovery/         Android multicast lock + iOS Bonjour browsing        ✅ M5 code, CI-compiled, ⚠️ no device run
apps/remote/                  Flutter UI: connect, remote, limitations, secure storage ✅ M3, M4, M7
supabase/migrations/          Optional accounts schema (RLS, no secrets)             ⚠️ M8, not provisioned
docs/                         Architecture, protocol notes, milestones, QA, release
```

## Documentation

| Document | Purpose |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | System design, layers, pairing, security, web strategy, risks, open questions |
| [docs/protocol-notes.md](docs/protocol-notes.md) | SSAP/SSDP reference with sources and a verified/unverified marker per claim |
| [docs/milestones.md](docs/milestones.md) | Milestone breakdown, acceptance criteria, agent ownership, branch/PR plan |
| [docs/qa-physical-tv-checklist.md](docs/qa-physical-tv-checklist.md) | The only accepted evidence that a command works on hardware |
| [docs/setup.md](docs/setup.md) | Toolchain, platform entitlements, running the mock TV and tests |
| [docs/sync.md](docs/sync.md) | Optional accounts: schema, RLS, and what is deliberately missing |
| [docs/release.md](docs/release.md) | Store metadata, privacy policy, release checklist, compatibility matrix |

## Working agreement

* `main` is protected. Work happens on feature branches: `docs/…`, `feat/…`, `fix/…`.
* CI runs on every push and pull request. Merges to `main` are blocked until the protocol, mock TV, app, Android build and iOS build checks pass; a green native build proves compilation, not hardware behaviour.
* One PR per milestone slice, reviewed before merge. Nothing is merged and nothing is pushed to production without explicit approval.
* Tests are written against a mock TV before physical TV testing; a mock-passing command is never described as "works on TV".
* No milestone proceeds by generating the whole application at once; each slice is reviewable on its own.

## Licence

Not yet chosen. Add `LICENSE` before the first public release.
