# docs/specs/macos-companion/02-overlooked-opportunities.md
---

# Overlooked Opportunities

What the neighbours do, what they systematically miss, and the position
that leaves open.

## The landscape

Four families of apps border this space. None occupies it.

### Clipboard managers — Paste, Maccy, CopyClip, Raycast clipboard history

Retention is their point: capture every copy, keep history, make the past
searchable. Excellent at what they do, and structurally unable to do what
we need:

- **History is a liability surface.** Every secret that transits the
  clipboard is recorded, indexed, and often synced. Their own mitigation —
  honouring `org.nspasteboard.ConcealedType` to *skip* password-manager
  content — is an admission that sensitive content and retention don't
  mix. Their answer is to look away; ours is to be the right place.
- **Automatic capture means zero intent.** The history is full of noise
  precisely because nothing in it was placed deliberately. Signal requires
  search, which requires an interface, which requires attention.
- **No time model.** Items age by scrolling out of relevance, not by
  expiring. Nothing in the UI answers "when does this stop existing?"
  because the answer is "never".

### Shelf apps — Yoink, Dropover, Unclutter

The closest neighbours in *ergonomics*: a drop target appears, holds files
and snippets mid-drag, and gets out of the way. They validated the
edge-docked, drag-first, present-not-centre-stage interaction. What they
miss:

- **No time model.** A shelf holds items until you remove them. In
  practice shelves silt up like any other surface.
- **No security posture.** No sensitivity semantics, no memory hygiene, no
  screen-capture awareness. Fine for dragging a PDF between windows; not a
  place anyone would stage a credential.
- **No exit ramp off the machine.** A shelf ends at the desktop's edge.
  The moment content must reach another person, you're back to Slack.

### Password managers — 1Password, Bitwarden, Keychain

The durable tier: encrypted, audited, permanent, correct. Their gap is
temporal and by design:

- They are archives, not staging areas. Creating a vault item for a
   90-second hold is category error, and everyone feels it — which is why
  those items end up in Notes instead.
- Their sharing flows are heavyweight (vaults, invitations, accounts on
  both ends) for the "send this one string to this one human once" case —
  the case Onetime Secret exists for.

### Secure senders — Onetime Secret itself, wormhole/croc, AirDrop

Point-to-point transfer, done well. Their gap is the *approach* to the
send:

- The web flow starts at a browser tab. The content is already in your
  clipboard — there's a copy-paste-navigate ritual between "I have the
  thing" and "I have the link", and the thing sits exposed in the
  single-slot clipboard the whole way.
- They are moments, not places. Nothing holds the content during the
  minutes or hours *before* it's ready to send, or the versions that
  accumulate along the way.

## The open position

Plotting the neighbours on two axes — **retention** (moment → forever) and
**sensitivity-fitness** (hostile to secrets → built for them) — the
quadrant *short-lived + secret-safe* is empty. Clipboard managers and
shelves sit in long-lived/hostile. Password managers sit in
forever/built-for-it. Secure senders are a point at moment/built-for-it
with no dwell time. **A visible, time-boxed, secret-safe staging area with
a one-click exit to secure transfer has no incumbent.**

## The overlooked opportunities, specifically

### 1. Time-remaining as the primary visual state

Everywhere else, expiry is buried metadata (a tooltip, a settings page).
Making the TTL the most prominent thing about each cell — a draining
visual cue plus a natural-time label — changes what the interface *is*: a
glance at the panel answers "what is in flight and how long does it have",
which is the only question a staging area needs to answer. No other app
renders time as the content's principal attribute.

### 2. TTL as direct manipulation, not configuration

The interactive label (click to cycle `1h → 3h → 8h → 24h → 3d → 7d`,
resetting the clock) collapses what would elsewhere be a preferences pane,
a per-item settings sheet, and a date picker into one affordance on the
cell itself. Two properties worth protecting: the vocabulary is *natural
time* (humans plan in "3 days", not timestamps), and the ceiling is low
(7 days is the maximum life; there is no "forever" on the wheel — the
absence of a keep-forever option is a design statement, not a missing
feature).

### 3. Deliberate placement as the privacy model

Because nothing is captured automatically, everything in the panel is
there by an intentional act. That single decision eliminates the entire
"my clipboard manager recorded my password" class of problem, makes the
panel's contents meaningful (100% signal), and keeps the mental model
honest: the user always knows what the app holds, because they put every
item there.

### 4. The promotion gradient

Local cell → Onetime Secret link is a *gradient of the same idea* —
ephemeral, view-limited content — extended from one machine to two
parties. Overlooked by everyone: senders have no staging, stagers have no
sending. Concretely: the cell's remaining TTL seeds the secret's TTL, the
API call is `POST /api/v3/secret/conceal`, the returned link lands in the
clipboard, and the local cell can offer to burn itself now that the
content has a better home. One click from "held here" to "en route,
one-time, encrypted" — with the content never passing through a browser
tab or sitting exposed in the clipboard along the way.

### 5. Ephemerality as the trust story for open source

"Secure scratch space" lives or dies on trust, and trust here is cheap to
earn honestly: the app is open source, the default store is memory-only,
there is no telemetry, no account, no server in the core loop. The claim
"it forgets" is auditable. A closed-source incumbent can't match that
posture cheaply; the web app's existing open-source credibility transfers.

### 6. Frugality as a differentiator, not a constraint

2026 desktop utilities trend toward 300 MB Electron residents. A Rust
menu-bar app that idles at near-zero CPU (no polling — TTL expiry
scheduled, not ticked), tens of MB of memory, single-digit MB download, no
background indexing, and no network until the user promotes something is a
felt difference on a laptop battery. Frugal also means frugal with
*attention* (no notifications by default) and *scope* (the anti-goals in
doc 01). See doc 03.

### 7. macOS security surface, actually used

The platform provides hooks that neighbours ignore or merely comply with;
this app can treat them as product features: mark its own copies with
`ConcealedType` (and a transient pasteboard type) so clipboard managers
ignore content leaving the panel; exclude the panel from screen capture
and screen sharing (`NSWindow.sharingType = .none`); offer clipboard
clear-after-copy with a countdown; hold cell contents in zeroized,
non-swappable memory. Individually small; together they make "the right
place to put a secret for an hour" a defensible technical claim, not a
slogan. Details in doc 05.

### 8. Accessibility in a category that ignores it

Menu-bar utilities are, as a class, keyboard-hostile and screen-reader
opaque — drag-and-drop-only interactions, unlabelled canvases, colour-only
state. A staging area whose every operation (add, inspect, extend, copy,
promote, discard) is keyboard-complete and VoiceOver-legible — with
time-remaining exposed as an accessibility value, not just a shrinking
ring — would be nearly alone in the category. Cheap to do from day one,
prohibitive to retrofit. Details in doc 05.

## Why incumbents won't follow

Worth writing down, since "empty quadrant" usually means either
opportunity or graveyard:

- Clipboard managers can add TTLs (some have auto-clear settings) but
  cannot abandon automatic capture and history — it *is* their product.
  Deliberate-placement-only is a rewrite of their value proposition, not a
  feature.
- Shelf apps could add timers, but without a security posture and an
  off-machine exit ramp they'd have a decaying shelf, not a staging area.
- Password managers adding a "temporary" tier would undermine their own
  archive-of-record positioning, and their trust model (everything in the
  vault, forever, audited) is the opposite promise.

And the graveyard risk is real: this quadrant is empty partly because it
resists monetization (nothing accrues, no lock-in, no data gravity). That
is survivable here precisely because the app is an open-source companion
whose strategic job is to make Onetime Secret more useful and more
present, not to be a business by itself. The absence of a business model
is the moat.
