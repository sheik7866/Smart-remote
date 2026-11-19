# Milestones and work breakdown

One PR per slice. Nothing merges without review approval; nothing ships as "working" without a signed row in [qa-physical-tv-checklist.md](qa-physical-tv-checklist.md).

## M0 — Architecture proposal *(current)*

**Owner:** Project Manager · **Branch:** `docs/architecture-proposal`

- Constraint analysis (platform, network, browser, LG firmware spread)
- Layer and module design, protocol abstraction, connection state machine
- Pairing, credential storage and security model
- Web strategy and its explicit limits
- Milestone plan, test strategy, QA checklist skeleton
- **Exit criteria:** the open questions in [architecture.md §13](architecture.md#13-open-questions-blocking-implementation) are answered and the proposal is approved.
- **No application code in this milestone.**

## M1 — Protocol core against a mock TV

**Owners:** LG Protocol Engineer, QA · **Branch:** `feat/ssap-core`

- `packages/webos_ssap`: frame codec, request multiplexer with timeouts, subscription registry, error taxonomy
- Transport abstraction with an injectable certificate policy (native: allow self-signed; web: not permitted)
- `tools/mock_tv`: scripted SSAP server (accept, deny, timeout, revoked key, `ws`-only and `wss`-only profiles, ARC `volume:-1` profile)
- Unit + integration tests over real sockets against the mock, using an injected clock
- **Exit criteria:** request/response, timeout, late-response and subscription paths covered by tests; `dart test` green.
- **Explicitly not claimed:** anything about real TV behaviour.

## M2 — Pairing and secure storage

**Owners:** Protocol Engineer, Flutter Developer, Security · **Branch:** `feat/pairing`

- Register/PROMPT pairing state machine: idle → awaiting TV prompt → paired / denied / timed out / revoked
- iOS Keychain and Android Keystore-backed store for `{host, port, secure, clientKey, modelName}`
- Key revoked → clear stored key, re-pair automatically, explain why
- Log redaction for keys; test that asserts keys never appear in logs
- **Exit criteria:** full pair → reconnect → revoked-key → re-pair cycle against the mock; security review signed off.

## M3 — Dark remote UI (no TV required)

**Owner:** Flutter Developer · **Branch:** `feat/remote-ui`

- Responsive layouts: phone (portrait), tablet, and a web-width variant
- Dark theme, large touch targets, haptics on press, accessibility labels and screen-reader order
- States: no TV yet, connecting, awaiting approval on TV, connected, degraded, error, TV asleep
- Controls wired to the controller API only — zero SSAP imports in the UI package
- **Exit criteria:** widget and golden tests; every control's disabled state has a visible reason.

## M4 — Live MVP commands

**Owners:** Protocol Engineer, Flutter Developer, QA · **Branch:** `feat/mvp-commands`

- Volume up/down (with press-and-hold coalescing), mute toggle reflecting real state, power off with confirmation
- D-pad, OK, back, home over the pointer socket
- Capability probe gates unsupported controls instead of failing silently
- **Exit criteria:** mock-backed tests green; then physical TV runs recorded in the checklist. Until then the UI shows no "verified" labelling.

## M5 — Discovery on native platforms

**Owners:** Protocol Engineer, Flutter Developer · **Branch:** `feat/discovery`

- Android: SSDP with multicast lock, Android 13+ `NEARBY_WIFI_DEVICES`, subnet probe fallback
- iOS: multicast entitlement path, Bonjour `_lg-mrt._tcp` fallback, local network usage description
- Manual "enter TV IP" always available as the escape hatch
- **Exit criteria:** discovery + manual entry both reach pairing on real hardware; failure states explain the likely network cause (VLAN, AP isolation, TV off).

## M6 — Resilience

**Owners:** Protocol Engineer, QA · **Branch:** `feat/reconnect`

- Reconnect with exponential backoff and jitter, single in-flight attempt, app-lifecycle aware
- Subscription re-establishment and state reconciliation after reconnect
- Latency instrumentation (local only, opt-in, no identifiers)
- **Exit criteria:** survives TV standby, router restart and network switch; no reconnect storms.

## M7 — Web client (limited, honest)

**Owner:** Web Engineer · **Branch:** `feat/web`

- Web build of the Flutter UI with manual-IP entry and a clear capability banner
- Explicit "browser limitations" screen: no discovery, no self-signed `wss`, no key persistence
- Bridge spike (timeboxed): same-origin local bridge over loopback HTTP, keys in the bridge's keystore, origin allowlist, token auth
- **Exit criteria:** documented decision on whether the bridge ships or the web client stays a LAN-only manual-IP client.

## M8 — Optional accounts and sync (post-MVP)

**Owners:** Flutter Developer, Security · **Branch:** `feat/sync`

- Supabase auth plus RLS-scoped tables for device **nicknames** and UI preferences only
- Schema test asserting no column can hold a key, token or MAC address
- **Exit criteria:** two-account isolation test; security review; keys provably absent from network traffic.

## M9 — Release

Store metadata, privacy policy (no telemetry by default), crash reporting with redaction, release checklist, version compatibility matrix.

## Agent ownership

| Agent | Primary scope | Signs off on |
| --- | --- | --- |
| Project Manager | Milestone plan, scope control, progress reports | Milestone exit criteria |
| Flutter Developer | `apps/remote`, `packages/remote_core` UI/state | UI, accessibility, responsive layout |
| LG Protocol Engineer | `packages/webos_ssap`, `tools/mock_tv`, discovery plugin | Protocol correctness, pairing, reconnect |
| Web Engineer | Web build, bridge research | Browser limits documented, nothing overclaimed |
| QA Engineer | Test strategy, mock scenarios, hardware matrix | Every physical-TV checklist row |
| Security Engineer | Pairing, storage, logging, threat model | Security review per milestone |

## Branch and PR policy

1. Branch from `main` per slice (`feat/…`, `fix/…`, `docs/…`).
2. Conventional commits, scoped (`feat(ssap): …`, `fix(pairing): …`).
3. PR description states what was tested, on mock or hardware, and what was **not** tested.
4. Required review: the owning agent plus Security for anything touching keys, storage or the manifest.
5. `main` is never force-pushed; production code is never overwritten; no auto-merge.
