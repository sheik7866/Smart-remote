# Physical LG TV testing checklist

This is the **only** accepted evidence that a command works. A green CI run against the mock TV proves protocol conformance, not hardware behaviour. Every row must be filled in on a real set before the README or release notes describe a feature as working.

## Test set register

| ID | Model | webOS version | Firmware | Audio setup | Network | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| TV-A | | | | TV speakers | 5 GHz Wi-Fi | |
| TV-B | | | | ARC soundbar | Ethernet | |
| TV-C | | | | Optical | 2.4 GHz Wi-Fi | |

Fill in at least three sets spanning an older and a newer webOS generation; include one set where only `wss://3001` works.

## 1. Discovery

| # | Test | Expected | TV-A | TV-B | TV-C |
| --- | --- | --- | --- | --- | --- |
| 1.1 | Cold launch on same subnet | TV appears within 5 s | | | |
| 1.2 | TV in standby | Still discoverable (or clear "TV is off" explanation) | | | |
| 1.3 | Manual IP entry | Reaches pairing even when discovery finds nothing | | | |
| 1.4 | AP client isolation enabled | Understandable failure message, not a spinner | | | |
| 1.5 | Different subnet/VLAN | Failure explained, no false positive | | | |

## 2. Pairing

| # | Test | Expected | TV-A | TV-B | TV-C |
| --- | --- | --- | --- | --- | --- |
| 2.1 | First pair, user accepts | Key stored, remote becomes usable | | | |
| 2.2 | User denies on TV | "Declined on TV", retry offered, no key stored | | | |
| 2.3 | No interaction on TV | Timeout with retry, no partial state | | | |
| 2.4 | Relaunch app | Reconnects without a new prompt | | | |
| 2.5 | Key revoked/forgotten on TV | App detects it, clears key, re-pairs | | | |
| 2.6 | Pairing over `wss` then forced `ws` | App knows the key is transport-bound, does not silently fail | | | |
| 2.7 | "LG Connect Apps" disabled on TV | Actionable guidance shown | | | |
| 2.8 | Key never in logs, crash report or network trace | Redaction verified with a proxy and log dump | | | |

## 3. Commands

| # | Test | Expected | TV-A | TV-B | TV-C |
| --- | --- | --- | --- | --- | --- |
| 3.1 | Volume up (10 presses) | Steps audibly, UI matches | | | |
| 3.2 | Volume down | Same | | | |
| 3.3 | Press-and-hold volume | Coalesced, no queue backlog after release | | | |
| 3.4 | Mute toggle | State matches TV OSD both ways | | | |
| 3.5 | Volume changed by the physical remote | App reflects it (subscription works) | | | |
| 3.6 | ARC soundbar volume | Step commands work; `setVolume` limitation explained if hit | | | |
| 3.7 | Power off | TV turns off, app shows disconnected state | | | |
| 3.8 | D-pad up/down/left/right | Moves focus with no duplicate presses | | | |
| 3.9 | OK / Back / Home | Correct action each time | | | |
| 3.10 | Repeat rate on D-pad hold | Smooth, no runaway | | | |
| 3.11 | Command latency on LAN | Perceived as immediate (record ms) | | | |

## 4. Connection handling

| # | Test | Expected | TV-A | TV-B | TV-C |
| --- | --- | --- | --- | --- | --- |
| 4.1 | TV enters standby, then wakes | Auto-reconnect, state re-synced, no duplicate subscriptions | | | |
| 4.2 | Router restart | Backoff, single retry loop, recovers when network returns | | | |
| 4.3 | Phone Wi-Fi → cellular → Wi-Fi | Fails clearly while off-LAN, recovers on return | | | |
| 4.4 | App backgrounded 10 minutes | Reconnects on foreground without a prompt | | | |
| 4.5 | Two phones paired to one TV | Both work; neither invalidates the other's key | | | |
| 4.6 | TV switched off at the wall | Clear "TV unreachable" state, no infinite spinner | | | |
| 4.7 | Certificate changes on TV | Fingerprint-change warning shown (diagnostic, not a block) | | | |

## 5. UI and accessibility

| # | Test | Expected | Result |
| --- | --- | --- | --- |
| 5.1 | Phone portrait / landscape | No clipped controls, safe-area respected | |
| 5.2 | Tablet layout | Layout uses the extra space deliberately | |
| 5.3 | Screen reader (VoiceOver / TalkBack) | Every button labelled, order logical | |
| 5.4 | Largest system font size | No truncation of error messages | |
| 5.5 | Unsupported control | Disabled with a reason, not a tap that does nothing | |
| 5.6 | Connection banner truthfulness | Never says "connected" while commands fail | |

## 6. Web client

| # | Test | Expected | Result |
| --- | --- | --- | --- |
| 6.1 | Served over `https`, TV needs `wss` | Blocked with the documented reason, no pretend success | |
| 6.2 | Served over loopback `http` with bridge | Commands work, key held by the bridge only | |
| 6.3 | Browser storage inspected | No pairing key in localStorage/sessionStorage/IndexedDB | |
| 6.4 | Discovery attempt in browser | Explained as unsupported, manual IP offered | |

## Sign-off

| Milestone | Tester | Date | TVs covered | Result |
| --- | --- | --- | --- | --- |
| M4 commands | | | | |
| M5 discovery | | | | |
| M6 resilience | | | | |
| M7 web | | | | |
