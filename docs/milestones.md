# Milestones and work breakdown

One PR per slice. Nothing merges without review approval; nothing ships as "working" without a signed row in [qa-physical-tv-checklist.md](qa-physical-tv-checklist.md).

## M0 — Architecture proposal ✅ approved 2026-11-19

**Owner:** Project Manager · **Branch:** `docs/architecture-proposal`

- Constraint analysis (platform, network, browser, LG firmware spread)
- Layer and module design, protocol abstraction, connection state machine
- Pairing, credential storage and security model
- Web strategy and its explicit limits
- Milestone plan, test strategy, QA checklist skeleton
- **Exit criteria:** the open questions in [architecture.md §13](architecture.md#13-open-questions-blocking-implementation) are answered and the proposal is approved.
- **No application code in this milestone.**

## M1 — Protocol core against a mock TV ✅ complete

**Owners:** LG Protocol Engineer, QA · **Branch:** `feat/ssap-core`

- `packages/webos_ssap`: frame codec, request multiplexer with timeouts, subscription registry, error taxonomy
- Transport abstraction with an injectable certificate policy (native: allow self-signed; web: not permitted)
- `tools/mock_tv`: scripted SSAP server (accept, deny, timeout, revoked key, `ws`-only and `wss`-only profiles, ARC `volume:-1` profile)
- Unit + integration tests over real sockets against the mock, using an injected clock
- **Exit criteria:** request/response, timeout, late-response and subscription paths covered by tests; `dart test` green.
- **Explicitly not claimed:** anything about real TV behaviour.
- **Evidence:** `packages/webos_ssap` 49 tests and `tools/mock_tv` 2 tests pass; `dart analyze` clean on both. Covers framing, multiplexing, timeouts, late responses, subscriptions, malformed frames, pairing accept/deny/timeout/revoke, transport fallback, self-signed TLS under both certificate policies, capability probing, ARC `volume:-1`, pointer sockets and log redaction. Still zero hardware claims.

**Scaffold ready:** `apps/remote` is a Flutter 3.50 app with the dark theme baseline, an empty-state home screen and a widget smoke test; `webos_ssap` is a path dependency. It is a shell only — the M3 visual design has not started.

## M2 — Pairing and secure storage ✅ complete

**Owners:** Protocol Engineer, Flutter Developer, Security · **Branch:** `feat/pairing`

- Register/PROMPT pairing state machine: idle → awaiting TV prompt → paired / denied / timed out / revoked
- iOS Keychain and Android Keystore-backed store for `{host, port, secure, clientKey, modelName}`
- Key revoked → clear stored key, re-pair automatically, explain why
- Log redaction for keys; test that asserts keys never appear in logs
- **Exit criteria:** full pair → reconnect → revoked-key → re-pair cycle against the mock; security review signed off.
- **Evidence:** `PairingController` (`packages/webos_ssap`) drives connecting → awaitingApproval → paired/denied/timedOut/revoked/failed, tries a stored key first, deletes a rejected key before prompting again, allows one attempt in flight, and reports failures instead of throwing. 11 controller tests over real sockets against the mock cover pair, relaunch-restore, revoke-and-repair, denial, timeout, unreachable TV, concurrent connects, a competing host, forget, an unreadable keystore and key redaction. `SecureCredentialStore` (`apps/remote`) writes one JSON record per TV through `flutter_secure_storage` (Keychain `first_unlock_this_device`, non-synchronisable; Android Keystore-backed AES-GCM); 7 tests cover round-trip, namespacing, overwrite, delete, `readAll` and corrupt records. The browser path uses `MemoryCredentialStore` and persists nothing.
- **Not yet done:** the Keychain/Keystore adapter is unit-tested against an injected backend only — it has not run on an iOS or Android device. Security review is still an open sign-off. Wiring the controller into the UI lands with M3.

## M3 — Dark remote UI (no TV required) ✅ code complete

**Owner:** Flutter Developer · **Branch:** `feat/remote-ui`

- Responsive layouts: phone (portrait), tablet, and a web-width variant
- Dark theme, large touch targets, haptics on press, accessibility labels and screen-reader order
- States: no TV yet, connecting, awaiting approval on TV, connected, degraded, error, TV asleep
- Controls wired to the controller API only — zero SSAP imports in the UI package
- **Exit criteria:** widget and golden tests; every control's disabled state has a visible reason.
- **Evidence:** the app now renders the full connect and remote experiences: phone single column and tablet/web two columns, dark high-contrast theme, haptics on every control, semantic labels for volume, mute, D-pad and OK, and an explicit reason under every disabled control. 28 widget tests cover the states and both layouts; `flutter analyze` clean. **Golden tests were deliberately not added** — layout is asserted through widget tests and dedicated wide/narrow keys, so there are no image fixtures to drift with the SDK.

## M4 — Live MVP commands ✅ mock-verified, hardware pending

**Owners:** Protocol Engineer, Flutter Developer, QA · **Branch:** `feat/mvp-commands`

- Volume up/down (with press-and-hold coalescing), mute toggle reflecting real state, power off with confirmation
- D-pad, OK, back, home over the pointer socket
- Capability probe gates unsupported controls instead of failing silently
- **Exit criteria:** mock-backed tests green; then physical TV runs recorded in the checklist. Until then the UI shows no "verified" labelling.
- **Evidence:** volume up/down with press-and-hold coalescing (one request in flight, nothing queued after release), mute reconciled against the TV, D-pad/OK/Back/Home/Info over the pointer socket, power off behind a confirmation, and capability gating with visible reasons. `remote_core` runs 28 tests against the mock TV, including pointer wire messages, the ARC `volume:-1` profile, denial handling and command failures. **No hardware run exists**, so nothing is labelled verified in the UI.

## M5 — Discovery on native platforms ✅ code complete, device-unverified

**Owners:** Protocol Engineer, Flutter Developer · **Branch:** `feat/discovery`

- Android: SSDP with multicast lock, Android 13+ `NEARBY_WIFI_DEVICES`, subnet probe fallback
- iOS: multicast entitlement path, Bonjour `_lg-mrt._tcp` fallback, local network usage description
- Manual "enter TV IP" always available as the escape hatch
- **Exit criteria:** discovery + manual entry both reach pairing on real hardware; failure states explain the likely network cause (VLAN, AP isolation, TV off).
- **Evidence:** SSDP `M-SEARCH` with the documented `urn:lge-com:service:webos-second-screen:1` target plus an `ssdp:all` sweep, LG detection and UPnP `friendlyName`/`modelName` enrichment are implemented in `remote_core`, with parser tests and an always-available manual-IP path. `plugins/lg_discovery` adds the native half: a Kotlin `WifiManager.MulticastLock` acquired and released around each sweep, and a Swift `NetServiceBrowser` for `_lg-mrt._tcp` that resolves services to IPv4. `CombinedDiscovery` merges SSDP and Bonjour, and tolerates one source failing. The plugin's 5 Dart tests and the merge tests pass. Android permissions (`INTERNET`, Wi-Fi state, `CHANGE_WIFI_MULTICAST_STATE`, `NEARBY_WIFI_DEVICES`) and iOS local-network/Bonjour usage strings are declared.
- **Subnet fallback:** when SSDP and Bonjour both return nothing, `SubnetProbeDiscovery` scans the private /24s around the device's IPv4 interfaces for ports 3000 and 3001 — at most 512 addresses, 48 concurrent attempts, 200 ms per connect, all bounded by the sweep deadline. Loopback, link-local and public ranges are ignored, and results are marked `DiscoverySource.subnetProbe`; the connect list labels them “found by network scan, confirm it is your TV” instead of presenting a port hit as a confirmed LG TV. Host caps, deadline, prefix filtering, cancellation and the fallback-only-when-empty rule are unit-tested. A sweep is cancellable: the controller owns a `DiscoveryCancellation` token, disposing the connect screen, tapping the Stop searching button or opening the limitations screen cancels it, the probe stops scheduling sockets within the current 200 ms attempt, and any late result is discarded.
- **Not verified:** the plugin now compiles in CI — the `android-build` job builds a debug APK and asserts `LgDiscoveryPlugin.class`, and `ios-build` builds the iOS app without signing and asserts `lg_discovery.framework` (run 44696732196, all seven jobs green) — but no sweep has run on a real network, device or TV. The probe's real socket scan has not run on a device either. iOS raw SSDP still needs Apple's multicast entitlement; Bonjour is the entitlement-free path there. Discovery is therefore **not** claimed to work on hardware; manual entry remains the supported path.

## M6 — Resilience ✅ mock-verified

**Owners:** Protocol Engineer, QA · **Branch:** `feat/reconnect`

- Reconnect with exponential backoff and jitter, single in-flight attempt, app-lifecycle aware
- Subscription re-establishment and state reconciliation after reconnect
- Latency instrumentation (local only, opt-in, no identifiers)
- **Exit criteria:** survives TV standby, router restart and network switch; no reconnect storms.
- **Evidence:** exponential backoff with bounded jitter (unit-tested), a single reconnect attempt in flight, reconnect pauses while the app is backgrounded and retries immediately on resume, stored-key restore without a second prompt, volume subscription re-established after reconnect, and opt-in local latency measurement. Tests drop the socket and assert recovery and the background pause. Router/standby/network-switch behaviour has **not** been exercised on hardware.

## M7 — Web client (limited, honest) ✅ build + limits, bridge not shipped

**Owner:** Web Engineer · **Branch:** `feat/web`

- Web build of the Flutter UI with manual-IP entry and a clear capability banner
- Explicit "browser limitations" screen: no discovery, no self-signed `wss`, no key persistence
- Bridge spike (timeboxed): same-origin local bridge over loopback HTTP, keys in the bridge's keystore, origin allowlist, token auth
- **Exit criteria:** documented decision on whether the bridge ships or the web client stays a LAN-only manual-IP client.
- **Evidence:** the web build compiles, shows the manual-IP client with a browser-limits banner, and refuses the TV connection with an explanation instead of failing silently; the in-app “Browser limitations” screen lists all five constraints, and the credential store is memory-only on web.
- **Decision:** the bridge is **not** shipped. It is a separate service with its own key custody and security review; the web client stays a manual-IP, LAN-only client. This is recorded in `docs/architecture.md` §8 and in the limitations screen.
- **Not verified:** no browser has been pointed at a real TV (the hosted page cannot accept the self-signed certificate, by design).

## M8 — Optional accounts and sync (post-MVP) ⚠️ schema only

**Owners:** Flutter Developer, Security · **Branch:** `feat/sync`

- Supabase auth plus RLS-scoped tables for device **nicknames** and UI preferences only
- Schema test asserting no column can hold a key, token or MAC address
- **Exit criteria:** two-account isolation test; security review; keys provably absent from network traffic.
- **Evidence:** `supabase/migrations/0001_preferences.sql` defines two RLS-scoped tables (nicknames and UI preferences) with `auth.uid() = user_id` policies and `anon` revoked; a schema guard test fails if any column name could hold a key, token, IP, MAC, SSID or address. `docs/sync.md` records the design and the activation steps.
- **Not done:** no Supabase project, no client code, no sign-in UI and no live two-account test. Accounts stay off in the shipped build, so this milestone is **not** signed off.

## M9 — Release ⚠️ artefacts drafted, not submitted

Store metadata, privacy policy (no telemetry by default), crash reporting with redaction, release checklist, version compatibility matrix.
- **Evidence:** `docs/release.md` contains the draft store metadata, the privacy policy, the crash-reporting redaction plan, the version compatibility matrix and a release checklist. `docs/sync.md` records the M8 decision.
- **Not done:** no store submission, no signing keys, no hosted privacy URL, no crash-reporting SDK, and `LICENSE` is still unset. The checklist is deliberately blocked on the physical-TV rows.

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
