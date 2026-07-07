# docs/specs/macos-companion/04-interaction-model.md
---

# Interaction Model (draft)

Supporting material for milestone 1 — a concrete sketch so the principles
in doc 03 can be argued against, not a finalized interface. Everything
here is revisable; the open questions it generates live in doc 06.

## Surfaces

### Menu bar item

The app's only permanent presence. Monochrome template icon, no badge, no
count. Click toggles the panel; drag-hover onto the icon opens the panel
to receive the drop. The menu (right-click) carries the boring necessities:
Settings, About, Quit — not features.

### The panel

A single column docked adjacent to a user-chosen screen edge (right edge
default), sized like a sidebar, visually quiet (system materials, respects
light/dark). Behaviour:

- **Non-activating.** Opening the panel does not deactivate the user's app
  (NSPanel semantics). Copy-out and TTL clicks work without the user
  losing their place; keyboard focus is taken only when explicitly
  summoned via hotkey.
- **Summon/dismiss.** Menu bar click, a global hotkey (configurable,
  keyboard-first users are first-class), and appearing automatically
  during any drag that hovers the docked edge (shelf-app convention).
  Dismisses on Esc, on click-outside, or stays pinned if the user pins it.
- **Excluded from capture.** The panel is invisible to screen sharing and
  screenshots by default (`sharingType = .none`); a visible indicator
  states this, and it is a setting, not a hidden behaviour.

### Layout, top to bottom

1. **Drop zone** — a generous, always-present target strip at the top.
   Also acts as the paste target: with the panel focused, ⌘V lands here.
2. **SleeperCells** — newest at top, a vertical stack of uniform cells.
3. **Footer whisper** — a single line: connection state to the Onetime
   Secret account *iff* one is configured; otherwise nothing.

The empty state is one sentence ("Drop or paste something on its way
somewhere else.") and dimmed keyboard-shortcut hints. No illustrations, no
onboarding carousel.

## Getting content in

| Route | Gesture | Notes |
| --- | --- | --- |
| Drag & drop | Onto panel, drop zone, or menu-bar icon | Text, RTF (flattened to plain), images, and promoted-file *contents* (small text/image files); not a file shelf — files themselves are out of scope initially |
| Paste | ⌘V with panel focused; global "paste to panel" hotkey | The global hotkey is the power path: stage the current clipboard without touching the mouse |
| Services / share ext. | "Stage in ‹app›" from selection | Later milestone |

On arrival a cell is created with the default TTL (proposed: **8h** — a
working day; see doc 06). No dialog, no naming step, no confirmation. The
cell appearing *is* the receipt.

## The SleeperCell

The unit of the interface. Anatomy, left to right:

```
┌────────────────────────────────────────────────┐
│ ◔  Aa  "postgres://ops:•••@db-3.internal…"     │
│        142 chars · pasted 14:02        [ 8h ]  │
│                                        ↗ link  │
└────────────────────────────────────────────────┘
  │   │   │                               │  └── promote CTA (subtle, hover/focus-revealed)
  │   │   └── recognition line: trimmed   └── interactive TTL label
  │   │       snippet or image thumbnail
  │   └── kind glyph (text / image / concealed)
  └── time-remaining cue (draining ring)
```

- **Time-remaining cue.** A small ring (or edge gauge) that visibly
  drains over the cell's life. Continuous, ambient, honest — the primary
  visual state per doc 02 §1. In the final hour it shifts along a second
  channel besides colour (thickness/texture) so urgency is not
  colour-only.
- **Recognition line.** First ~60 chars of text (middle-ellipsized) or an
  image thumbnail, plus a metadata whisper (size, arrival time). Content
  detected as secret-shaped (arrived with `ConcealedType`, or matches
  key/token patterns) renders masked by default with a reveal-on-hold.
- **Interactive TTL label.** Reads as natural time remaining ("8h",
  "3d"). Click to cycle the ladder `1h → 3h → 8h → 24h → 3d → 7d → 1h`,
  each click *resetting* the clock to the shown value. One affordance for
  extend, shorten, and reset; no menus, no pickers. Scroll/arrow-keys on
  the focused label also step it.
- **Promote CTA.** A quiet "↗ link" revealed on hover/focus (always
  present to assistive tech). See promotion flow below.

### Cell interactions

| Intent | Mouse | Keyboard (panel focused) |
| --- | --- | --- |
| Copy back out | Click cell body | ↑/↓ to select, ⏎ to copy |
| Copy + auto-clear clipboard | ⌥-click | ⌥⏎ |
| Cycle TTL | Click label | T, or ←/→ on label |
| Peek (read-only overlay) | Space / long-hover *action*, not content-on-hover | Space |
| Promote to secret link | Click "↗ link" | L |
| Discard now | Hover ✕, or drag out of panel | ⌫ (with brief inline undo) |

Copy-out places the content on the clipboard marked with
`org.nspasteboard.ConcealedType` + a transient type, so clipboard
managers ignore it. Copy-out does **not** consume the cell (multi-paste is
a core moment, doc 01) — the cell simply keeps draining.

### Cell lifecycle

`staged → draining → last-hour (urgency cue) → expired (removed; content
zeroized)`. Expiry is silent by default: the cell is simply gone at next
glance. A cell being promoted passes through `promoting → promoted`
(shows the one-time link was copied, offers **Burn local copy**) and then
resumes draining if kept.

The panel holds a small working set — soft cap around a dozen cells
(exact number: doc 06). At the cap, the panel refuses gently and asks the
user to let something expire or discard, rather than silently evicting
the oldest: silent eviction of deliberately-placed content would break
trust (doc 03 §5) — the cache analogy yields eviction *by policy*, and
here the policy is the TTL the user chose, never LRU surprise.

## Promotion flow (secondary interaction)

One click from cell to shareable one-time link:

1. Click "↗ link" (or L). If no account is configured, this is the single
   place the app ever mentions accounts: an inline hint linking to
   Settings → Connection, plus a guest-mode option where the server
   allows it.
2. An inline, in-cell confirmation (not a modal): destination
   (`share_domain`), TTL (seeded from the cell's remaining time, snapped
   to the server's allowed values), optional passphrase, optional
   recipient. One confirming click. The network boundary is explicit —
   this is the app's only outbound action (doc 03 §6).
3. `POST /api/v3/secret/conceal` (Basic auth: org `extid` + API token,
   until PASETO lands). On success the link is on the clipboard, the cell
   shows `promoted` with the receipt identifier, and offers **Burn local
   copy**.
4. Failure is inline in the cell (offline, auth, entitlement/TTL
   rejection) with a retry; content never leaves the cell on failure.

Deliberately absent from v1: browsing receipts, burning remote secrets
from the panel, secret generation. The panel is a staging area with an
exit ramp, not an API console.

## Settings (one small window)

Connection (server URL, org `extid` + API token, share domain, test
button), default TTL, dock edge, hotkeys, clipboard clear-after-copy
timing, screen-capture exclusion toggle, launch at login. That's the
whole list; growth here is a smell.
