# LG webOS SSAP — working protocol notes

This file records what we currently believe about the protocol, with the source and a confidence marker. **Anything marked `UNVERIFIED` must be confirmed against a real television before it is relied on or described as working.**

Legend: ✅ confirmed by multiple independent implementations · ⚠️ single source or model-specific · ❓ unverified / to be tested on hardware.

## 1. Discovery

| Fact | Confidence | Source |
| --- | --- | --- |
| SSDP multicast: `M-SEARCH` to `239.255.255.250:1900`, `MX: 5`, `MAN: "ssdp:discover"` | ✅ | lgtv2, ConnectSDK, sample node client |
| Search target: `ST: urn:lge-com:service:webos-second-screen:1` | ✅ | ConnectSDK `WebOSTVService.discoveryFilter()`, reMaestro docs |
| Response `LOCATION` points at a device-description XML carrying `friendlyName`, `modelName` | ⚠️ | ConnectSDK parser |
| LG responds to SSDP but not mDNS; `_lg-mrt._tcp` Bonjour advertisement exists as a fallback signal | ⚠️ | reMaestro docs, Smart-TV-Remote-Control notes |
| Android needs a `WifiManager.MulticastLock` to receive multicast replies | ✅ | multiple Android implementations |
| iOS needs `com.apple.developer.networking.multicast` for raw multicast; Bonjour needs no entitlement | ⚠️ | Apple entitlement docs, community reports |
| Discovery fails across VLANs / with AP client isolation enabled | ✅ | inherent to multicast + common reports |

## 2. Transport

| Fact | Confidence | Source |
| --- | --- | --- |
| Plain: `ws://<host>:3000` · Secure: `wss://<host>:3001` | ✅ | lgtv2, ConnectSDK, zapper research |
| Certificate on 3001 is self-signed and issued to an internal LG hostname; clients must not verify it | ✅ | lgtv2 docs, zapper research, lgtv-remote PROTOCOL.md |
| Many 2022/2023+ sets accept **only** the secure port | ✅ | lgtv2 README, lgtv-remote PROTOCOL.md |
| Pre-2018 sets commonly offer only plain 3000 | ✅ | lgtv2 README |
| One WebSocket carries all requests, responses and subscriptions, multiplexed by a client-chosen `id` | ✅ | lgtv-remote PROTOCOL.md |
| Frames are UTF-8 JSON text, no binary framing, no compression, no length prefix | ✅ | lgtv-remote PROTOCOL.md |
| Pairing is **per transport**: a key obtained over `wss` is not honoured on `ws`, so the chosen transport must be stored with the key | ✅ | lgtv-remote PROTOCOL.md |
| `ws://` cannot be opened from a page served over `https://` (mixed content) | ✅ | browser platform rule |

## 3. Pairing

First frame on a fresh connection must be `register`; nothing else is answered until pairing completes.

```json
{"id":"register_0","type":"register","payload":{
  "forcePairing":false,
  "pairingType":"PROMPT",
  "manifest":{ "...": "..." }
}}
```

| Fact | Confidence | Source |
| --- | --- | --- |
| Valid stored key → immediate `{"type":"registered","payload":{"client-key":"…"}}` | ✅ | lgtv-remote PROTOCOL.md, zapper research |
| No/revoked key → `{"type":"response","payload":{"pairingType":"PROMPT","returnValue":true}}`, TV shows an approval dialog with roughly a 60 s window | ✅ | lgtv-remote PROTOCOL.md |
| User accepts → `{"type":"registered","payload":{"client-key":"…"}}` | ✅ | same |
| User denies → error with 403 / "cancelled" | ⚠️ | Smart-TV-Remote-Control notes |
| `pairingType:"PIN"` variant exists, code shown on TV, completed with `ssap://pairing/setPin {pin}` | ⚠️ | community docs |
| Manifest must list the permissions the app needs; `aiowebostv` / ConnectSDK manifests are the reference sets | ⚠️ | zapper research |
| A signed manifest is preferred; some firmware rejects blacklisted certificates, so an unsigned fallback is needed | ❓ | single community source — test both |
| On many models the user must enable "LG Connect Apps" / "Mobile TV On" for pairing to be offered | ⚠️ | lgtv2 README, reMaestro docs |

## 4. Commands (MVP surface)

Envelope: `{"type":"request","id":"<n>","uri":"ssap://…","payload":{…}}` → `{"type":"response","id":"<n>","payload":{"returnValue":true,…}}`.

| Capability | URI | Payload | Confidence |
| --- | --- | --- | --- |
| Volume up / down | `ssap://audio/volumeUp`, `ssap://audio/volumeDown` | — | ✅ |
| Absolute volume | `ssap://audio/setVolume` | `{"volume": 0-100}` | ✅ |
| Mute | `ssap://audio/setMute` | `{"mute": true}` | ✅ |
| Volume state / subscription | `ssap://audio/getVolume` (`subscribe:true`) | — → `{volume, muted, changed}` | ✅ |
| Power off | `ssap://system/turnOff` | — | ✅ |
| Pointer/navigation socket | `ssap://com.webos.service.networkinput/getPointerInputSocket` | — → `{socketPath}` | ⚠️ |
| Channel up / down | `ssap://tv/channelUp`, `ssap://tv/channelDown` | — | ✅ |
| Media transport | `ssap://media.controls/play|pause|stop|rewind|fastForward` | — | ✅ |
| Launch app | `ssap://system.launcher/launch` | `{"id": appId}` | ✅ |
| Foreground app | `ssap://com.webos.applicationManager/getForegroundAppInfo` (`subscribe`) | — | ⚠️ |
| External inputs | `ssap://tv/getExternalInputList`, `ssap://tv/switchInput` | `{"inputId": …}` | ⚠️ |
| Service list (capability probe) | `ssap://api/getServiceList` | — | ⚠️ |
| Power state | `ssap://com.webos.service.tvpower/power/getPowerState` (`subscribe`) | — | ⚠️ |
| Network status / MAC (for Wake-on-LAN) | `ssap://com.webos.service.networkinterface/getNetworkStatus` | — | ❓ |
| Screen off (not full power off) | `ssap://com.webos.service.tvpower/power/turnOffScreen` | — | ⚠️ |
| Sound output list | `ssap://com.webos.service.apiadapter/audio/getSoundOutput` | — | ⚠️ |

### Error strings seen in the wild

`404` no such service or method · `401` insufficient permissions (manifest) · `403` access denied / denied by user · `500` application error.

### Known capability traps

* **ARC/eARC soundbars:** the TV may report `volume: -1`, so absolute `setVolume` does nothing useful. Step commands (`volumeUp`/`volumeDown`) are the reliable path on those setups. ⚠️
* **`setMute` vs. soundbar mute:** muting the TV does not necessarily mute an ARC device. ⚠️
* **Power on** is not an SSAP command — it needs Wake-on-LAN (UDP magic packet to port 9) with the TV's MAC address, and "Mobile TV On"/network standby must be enabled. Out of MVP scope. ⚠️
* **Navigation button names** (`UP`, `DOWN`, `LEFT`, `RIGHT`, `ENTER`, `BACK`, `HOME`, `EXIT`, `INFO`, `DASH`, digits, colours) are sent over the pointer socket as `{"type":"button","name":"…"}`; exact support varies by model. ❓
* **Pointer socket lifecycle:** it is a second WebSocket, invalidated whenever the main session drops; it must be reopened after every reconnect. ⚠️

## 5. What this means for the architecture

1. Try `wss://:3001` first, fall back to `ws://:3000`, and remember the transport that worked — together with the key.
2. Never verify the TV certificate on native, but record its SHA-256 fingerprint and alert on change (trust on first use, not enforcement).
3. Probe capabilities after pairing and drive the UI from that, rather than from a hardcoded "LG TV" feature set.
4. Treat all of the above as hypotheses until the QA checklist records real hardware results.

## Sources

* lgtv2 (hobbyquaker) — transports, URI table, ARC volume caveat
* lgtv-remote `docs/PROTOCOL.md` — pairing sequence, per-transport keys, framing
* zapper `docs/research/tv-remote-protocols.md` — permissions manifest, pairing variants, input boundaries
* ConnectSDK `WebOSTVService.java` — SSDP filter, capability parsing
* reMaestro webOS driver docs — ports by generation, SSDP-not-mDNS, WoL/MAC handling
* Sample node webOS client gist — raw M-SEARCH contents
