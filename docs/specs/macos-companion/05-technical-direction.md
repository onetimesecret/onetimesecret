# docs/specs/macos-companion/05-technical-direction.md
---

# Technical Direction (draft — survey, not decisions)

Milestone-1 supporting material. Records the option space and provisional
leanings so milestone 2 can make decisions against something written down.

## Architecture shape (held constant across all options)

A UI-agnostic core crate plus a thin shell:

```
┌─────────────────────────────────────────────┐
│ shell (one of the options below)            │
│   panel window · tray · drag-drop · a11y    │
├─────────────────────────────────────────────┤
│ core crate (pure Rust, no UI deps)          │
│   cell store (memory-only, zeroizing)       │
│   TTL scheduler (timer wheel, no polling)   │
│   pasteboard adapter (NSPasteboard, kinds,  │
│     ConcealedType read/write)               │
│   ots-client (v3 API, auth strategies)      │
│   secret-shape detection (heuristics)       │
└─────────────────────────────────────────────┘
```

The core crate is testable headless and survives a shell swap — which is
exactly the hedge the framework question needs.

## Shell options (Rust, macOS, 2026)

| Option | What it is | For | Against |
| --- | --- | --- | --- |
| **Tauri 2.x** | System-WebKit shell, Rust backend | Mature tray + window APIs; tiny bundle vs Electron; a11y inherits WebKit/ARIA (strong); huge ecosystem; team's web skills (Vue/TS in this repo) transfer to the panel UI | Webview memory floor (~tens of MB); NSPanel non-activating behaviour needs objc2 side-door; JS layer to keep honest with the frugality principle |
| **Swift/AppKit shell + Rust core (UniFFI/swift-bridge)** | Native shell, Rust logic | Best-in-class NSPanel, menu bar, drag-drop, VoiceOver — the exact surfaces this app lives on; smallest resident footprint | Two languages/toolchains; contributors need both; "Rust-based" becomes "Rust-cored"; more release engineering |
| **gpui** | Zed's GPU-native Rust UI | Truly native-feeling Rust UI, proven at Zed scale; excellent perf | Young as a third-party dependency; a11y story still maturing; menu-bar/panel patterns less trodden |
| **egui/eframe + AccessKit** | Immediate-mode Rust UI | Simple, small, AccessKit gives real a11y; fast to prototype | Non-native look (fights "furniture" goal); immediate-mode repaint vs near-zero idle CPU needs care |
| **Slint / Dioxus native** | Declarative Rust UI | Clean component model; Slint has decent a11y | Neither is battle-tested for menu-bar utility UX on macOS |

**Provisional leaning:** Tauri 2.x shell with `objc2` for the few native
behaviours it lacks (non-activating NSPanel, `sharingType`,
pasteboard types), on the strength of maturity + a11y + contributor
accessibility — with the Swift-shell option kept live as the
better-native fallback, made cheap by the core-crate architecture.
Decision belongs to milestone 2 after a two-way spike: the panel
experience (non-activating, edge-docked, drag-in) is the make-or-break
surface to prototype in both.

Non-negotiables regardless of shell: signed + notarized, universal binary
(arm64 first), sandboxed if feasible (pasteboard and network entitlements
are compatible; verify against capture-exclusion APIs), single-digit MB
download as a target, no always-resident helper processes.

## Security posture

The claims in docs 02–03, made implementable:

- **Memory-only by default.** Cells live in RAM; process exit is total
  amnesia (v1 behaviour; persistence across restart is an open question).
  Buffers zeroized on expiry/discard (`zeroize`), `mlock` where practical
  for small secret-shaped payloads; large images excluded from `mlock`
  and documented as such.
- **Zeroization is why the core is Rust.** Swift is memory-safe but not
  memory-hygienic: `String`/`Data` are copy-on-write, ARC/autorelease and
  `NSString` bridging create uncontrolled copies, and there is no blessed
  way to zeroize a `String`. Rust ownership makes the wipe deterministic.
  Platform security APIs (Keychain, CryptoKit, `sharingType`, Sandbox)
  are equally reachable from any shell and don't differentiate; buffer
  lifecycle does.
- **Rendering vs residence.** Displaying a secret in a UI layer for the
  moments a human reads it is a normal, accepted exposure — browsers do
  secure work all day, including Onetime Secret itself. The rule is about
  *residence*: the authoritative copy lives at rest only in the zeroizing
  core; any shell's UI layer (DOM included) receives plaintext
  transiently, on demand, for display, and never retains it in frontend
  state for the cell's lifetime. Copy-out goes core → pasteboard
  directly, not through the UI layer. Residual heap/crash-dump copies in
  a webview process are a real but marginal exposure under the threat
  model below — a scoring criterion for the shell decision, not a gate.
- **Pasteboard hygiene.** Outbound copies marked
  `org.nspasteboard.ConcealedType` + transient; inbound `ConcealedType`
  respected by masking the cell by default. Optional clear-after-copy
  (clear the system clipboard N seconds after a copy-out, only if the
  clipboard still holds our change-count).
- **Capture exclusion.** Panel `NSWindow.sharingType = .none` by default,
  surfaced honestly in the UI as a toggle.
- **Network boundary.** Exactly one outbound destination (the configured
  OTS server), TLS-only, only on explicit promotion. No telemetry, no
  update pings beyond a launch-time check against the release feed.
- **Credential storage.** API token in the macOS Keychain, never in
  config files.
- **Threat honesty.** Out of scope and said so: a compromised local user
  account, kernel-level attackers, and other apps with screen-recording +
  accessibility permissions granted. The app hardens the common cases
  (shoulder surfing, screen sharing, clipboard-manager retention, swap,
  crash dumps) and does not pretend to be an enclave.

## Onetime Secret v3 API integration

Grounded in the current repo (`apps/api/v3/routes.txt`,
`src/schemas/api/v3/`):

- **Promotion** → `POST /api/v3/secret/conceal` with
  `{ kind: "conceal", secret, ttl, share_domain, passphrase?, recipient? }`.
  Cell-remaining-TTL seeds `ttl`, snapped to server-permitted values;
  entitlement rejections (cf. `secret_ttl_entitlement_spec.rb`) surface
  inline with the nearest allowed value offered.
- **Auth, phase 1:** HTTP Basic (`basicauth` strategy — API key + secret
  pair, configured alongside the organization `extid`), stored in
  Keychain. **Phase 2:** PASETO bearer tokens when v3 auth ships; the
  `ots-client` crate isolates auth as a strategy trait so the swap is
  additive.
- **Guest mode:** where the server enables guest route gating,
  `POST /api/v3/guest/secret/conceal` allows promotion with no account —
  worth supporting so the open-source app is fully useful against
  self-hosted instances with zero setup.
- **Post-promotion:** store only the receipt identifier on the live cell
  (for a "burn remote" affordance on that cell alone). No receipt
  browsing, no local history of promoted secrets (doc 03 §5).
- **Server config:** `GET /api/v3/status` + config endpoints at
  connection-test time to learn allowed TTLs and share domains, cached in
  memory only.

## Accessibility commitments

Category-defying per doc 02 §8; committed now because retrofits fail:

- **Keyboard-complete.** Every operation in doc 04's table has a binding;
  the global summon hotkey focuses the panel for full keyboard operation.
- **VoiceOver-legible.** Each cell is one accessibility element with a
  composed label ("Text, postgres URL, 142 characters, expires in 7
  hours"); the TTL label is an adjustable control (VO-arrows step the
  ladder); the draining ring mirrors into an accessibility value that
  announces at coarse thresholds only (no chatter).
- **Not colour-only.** Urgency encoded in ring geometry + label text, not
  hue alone; WCAG 2.2 AA contrast against both system materials.
- **Motion-respectful.** `prefers-reduced-motion` swaps the draining
  animation for stepped states; no parallax, no bounce.
- **Text scaling.** Cells reflow with system text size; the panel is a
  column, so this is layout-cheap if honoured from the first sketch.

## Frugality budget (v1 targets, measured in CI once real)

| Metric | Target |
| --- | --- |
| Download size | < 10 MB |
| Resident memory, idle w/ 5 cells | < 60 MB (Tauri) / < 25 MB (native shell) |
| Idle CPU | ~0% (no timers ticking; TTL expiry scheduled) |
| Wakeups | No periodic wakeups while panel hidden |
| Network at rest | Zero connections |
| Cold launch to usable panel | < 300 ms |
