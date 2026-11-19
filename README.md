# Smart Remote — LG TV

A polished, reliable remote control for LG webOS televisions, built with Flutter for iOS and Android, plus a browser client.

> **Status: Milestone 0 — architecture proposal. No application code yet.**
> The proposal is at [docs/architecture.md](docs/architecture.md). Implementation starts only after the open questions in that document are answered.

## Mission

Control an LG webOS TV from a phone or a browser on the same local network: discover the TV, pair with on-screen approval, then send volume, mute, power-off and navigation commands — with honest connection status and useful errors instead of silent failure.

## Principles

1. **Local only.** Every control packet travels directly from the app to the TV over the LAN. No cloud relay, no tunnelling of control ports to the internet.
2. **Keys stay on the device.** The webOS `client-key` is written only to iOS Keychain, Android Keystore-backed storage, or a native bridge's keystore. It is never sent to Supabase or any backend, never logged, never attached to telemetry.
3. **Capabilities are discovered, not assumed.** LG webOS differs across models, firmware and audio setups (for example ARC soundbars reporting volume `-1`). The app probes and disables what a TV does not support.
4. **No unverified claims.** A command is "working" only when a row in the physical TV checklist has been signed off against a real set. CI passing proves protocol conformance, not hardware behaviour.
5. **Protocol is independent of the UI.** `packages/webos_ssap` is plain Dart with no Flutter imports; the UI consumes a typed controller API.

## Repository layout (proposed)

```
apps/remote/                  Flutter app — iOS, Android, web
packages/webos_ssap/          Dart SSAP protocol: transport, session, pairing, commands
packages/remote_core/         App state, command orchestration, capability model
plugins/lg_discovery/         Federated plugin: SSDP on Android, Bonjour/multicast on iOS
tools/mock_tv/                Mock SSAP TV server for tests and local development
docs/                         Architecture, protocol notes, milestones, QA checklist
```

## Documentation

| Document | Purpose |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | System design, layers, pairing, security, web strategy, risks, open questions |
| [docs/protocol-notes.md](docs/protocol-notes.md) | SSAP/SSDP reference with sources and a verified/unverified marker per claim |
| [docs/milestones.md](docs/milestones.md) | Milestone breakdown, acceptance criteria, agent ownership, branch/PR plan |
| [docs/qa-physical-tv-checklist.md](docs/qa-physical-tv-checklist.md) | The only accepted evidence that a command works on hardware |
| [docs/setup.md](docs/setup.md) | Toolchain, platform entitlements, running the mock TV and tests |

## Working agreement

* `main` is protected. Work happens on feature branches: `docs/…`, `feat/…`, `fix/…`.
* One PR per milestone slice, reviewed before merge. Nothing is merged and nothing is pushed to production without explicit approval.
* Tests are written against a mock TV before physical TV testing; a mock-passing command is never described as "works on TV".
* No milestone proceeds by generating the whole application at once; each slice is reviewable on its own.

## Licence

Not yet chosen. Add `LICENSE` before the first public release.
