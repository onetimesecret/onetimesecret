# docs/specs/macos-companion/01-problem-space.md
---

# Problem Space

## The busiest, least-designed surface on the desktop

The clipboard is the highest-traffic data conduit on any computer, and it
has barely been designed at all. It is a single anonymous register: one
slot, no history, no expiry, no notion of sensitivity, silently readable
by any foreground application (macOS 15 finally added paste prompts, but
the model is unchanged). Every password, 2FA code, API token, address,
screenshot, and half-written paragraph passes through it — and the user's
mental model of "where that thing is right now" is a coin flip.

### Sidebar: fifty years of prior art at the system level

"Least-designed" is not the same as "never attempted" — the lineage is
worth having on the record, because it shows the gap is a *declined*
design, not an overlooked one.

- **Origin.** Cut/copy/paste comes from Larry Tesler and Tim Mott's Gypsy
  editor at Xerox PARC (1975), the names taken literally from paper-era
  manuscript editing; Tesler credited Pentti Kanerva's earlier insight
  that a deletion buffer could double as a transfer mechanism. Apple's
  Lisa and Macintosh (1983–84) made it system-wide, named it "the
  Clipboard", and fixed the ⌘X/C/V bindings. The model — one anonymous
  slot, no expiry, no sensitivity — has not changed since.
- **Before it.** Delete buffers and yank registers in line editors: TECO,
  vi's named registers, the Emacs kill ring. The kill ring is a
  *multi-slot* clipboard from the 1970s — the "clipboard manager" idea
  predates the single-slot design that won.
- **System-level attempts, mostly dead.** Apple's Scrapbook (a persistent
  multi-item store, shipped in System 1, quietly abandoned); System 7's
  Publish & Subscribe and Windows DDE/OLE (live links instead of copies —
  a mental model users never adopted); NeXTSTEP's Shelf (spatial staging,
  the direct ancestor of today's shelf apps); X11's ownership model,
  where the "clipboard" is a pointer into the source app and the data
  dies when that app quits.
- **The integration that *did* happen — and its hedges.** OS vendors
  eventually shipped clipboard history: Windows added Win+V history and
  cloud sync in 2018, KDE has bundled Klipper for decades, Apple did
  Universal Clipboard across devices. But Windows ships history **off by
  default**, and Apple has conspicuously never added history at all —
  adding *counter*-features instead (`org.nspasteboard.ConcealedType`,
  iOS paste-access prompts). Clipboard traffic is dense with credentials,
  and retention turns a transfer mechanism into a liability archive. The
  vendors aren't overlooking retention; they're declining it.

So the unsolved quadrant is not *remember more* — that has been tried,
integrated, and deliberately hobbled. It is *hold briefly, then verifiably
forget*, and nobody has shipped it at the system level.

Because the clipboard is so inadequate, people improvise **staging areas**
— places to put content that is *between* an origin and a destination:

- A password copied from a vault, needed again in ninety seconds for the
  confirmation field.
- A 2FA recovery code that must survive a reboot but not the week.
- A screenshot of an error dialog, en route from one machine or one
  conversation to another.
- A license key mid-way through a reinstall.
- A paragraph cut from one document, destined for another that isn't open
  yet.
- An address, a booking reference, a Wi-Fi password read aloud from a
  phone.

The improvised staging areas are all wrong in the same direction — they
**retain**:

| Improvised staging area | What goes wrong |
| --- | --- |
| Clipboard manager history | Records *everything*, indefinitely, searchable — a liability, not a convenience, the moment a secret passes through |
| Notes app / stickies | Permanent by default; secrets fossilize in "Untitled 47", synced to a cloud account |
| Slack/email message to self | Persists on someone else's servers, indexed, discoverable |
| A TextEdit window never saved | Lost on crash or restart — or worse, auto-saved somewhere |
| Files on the Desktop | Pile up, get backed up, get screen-shared |
| The clipboard itself | One slot; the next copy destroys the thing you were staging |

The problem is not storage. Storage is solved, oversolved. The problem is
**staging**: a place designed for content whose defining property is that
it is *in transition* and should stop existing when the transition ends.

## The cache analogy, taken seriously

The brief frames the app as "an L1/L2 cache for the clipboard", and the
analogy holds up under weight — it is the spec in miniature:

1. **Small.** A cache holds a working set, not an archive. A dozen cells,
   not a thousand rows of history. Smallness is what keeps the whole state
   legible at a glance.
2. **Close.** One keystroke or one glance away, docked at the edge of the
   screen — in peripheral vision, adjacent to the work, never in front of
   it.
3. **Evicts by policy, not by user labour.** Nobody "cleans up" a CPU
   cache. Every entry has a TTL from the moment it arrives; expiry is the
   default lifecycle, and *keeping* something is the action that requires
   intent (resetting or extending the TTL).
4. **Never authoritative.** A cache never owns the data; the source of
   truth is elsewhere. Losing a cell is at worst a minor re-fetch, never a
   catastrophe. This single property is what lets the app stay calm — no
   sync, no backup, no versioning, no anxiety.
5. **Optimized for one access pattern.** Caches win by refusing
   generality. This app is optimized for *put → brief hold → copy out →
   forget*, and declines every workload outside that pattern.

The one place the analogy is deliberately extended: a cache line can be
**written back** to a slower, more durable tier. Here the write-back path
is promotion to a Onetime Secret link — the moment content stops being
"mine, in transit between my own contexts" and becomes "shared, in transit
to someone else". Same lifecycle philosophy (one view, then gone), one
tier further out.

## Ephemerality is the feature, not the compromise

Every neighbouring product treats retention as the value and expiry as a
setting. This product inverts that: **the guarantee of disappearance is
the value.**

That inversion is what makes it trustworthy for sensitive content.
Clipboard managers must *exclude* password managers (via
`org.nspasteboard.ConcealedType`) because their retention makes them a
hazard. A staging area that provably forgets is the one place on the
desktop where a password in transit is *supposed* to be. Users don't have
to weigh convenience against hygiene — the convenient thing and the
hygienic thing are the same thing.

It also removes the accumulation tax. Tools that retain accrue baggage:
the 4,000-item history, the graveyard of stickies, the "someday I'll sort
this" folder. Each is a small standing debt of attention. A tool where
everything self-cleans owes the user nothing and asks nothing back. Empty
is its natural, healthy state — an empty panel is the system working, not
the product failing at engagement.

## Present, but not centre stage

The app lives in the menu bar with a panel docked adjacent to a screen
edge. It is furniture: glanceable, reachable, and otherwise invisible. It
never demands attention — no badges, no counters, no notifications begging
for interaction. Content plays "second or third fiddle": cells *summarize*
what they hold (a snippet, a thumbnail, a size); they are handles for
moving content, not a reading or editing surface.

The honest success metric is *seconds of user attention consumed per
transfer*, minimized — the opposite of engagement. A perfect session is:
drop, glance, copy, and the app is forgotten until next time.

## Who it's for, concretely

Not personas — moments. The same person hits all of these in a week:

- **The relay.** Copy from A, but B isn't ready yet. (Vault → form that
  needs three fields; terminal → ticket being written; phone photo →
  document.)
- **The multi-paste.** One source, several destinations over ten minutes,
  with other copying happening in between. The single-slot clipboard makes
  this a juggling act.
- **The overnight hold.** Needed tomorrow morning, radioactive by Friday.
  (Recovery code during a device migration; credentials during onboarding
  week.)
- **The hand-off.** The content must leave the machine — to a colleague, a
  client, another device. This is the promotion moment, and the only
  moment the network appears.

## Anti-goals

Stated early because scope discipline *is* the product:

- **Not a clipboard history.** No automatic capture of clipboard changes.
  Everything in the panel was placed there deliberately. (Automatic
  capture is precisely the liability this app exists to avoid.)
- **Not a notes app.** No editing beyond trivial trimming, no formatting,
  no organization, no folders, no tags.
- **Not a search index.** A dozen glanceable cells need eyes, not a query
  language. If it needs search, it has failed the "small" property.
- **Not a sync service.** No cloud, no accounts for the core loop, no
  state that outlives the machine (initially, no state that outlives the
  process — see open questions).
- **Not sticky.** No streaks, no counters, no upsell surface area, no
  reasons to open it beyond having content in hand. Comfortable being
  forgotten between uses.
- **Not a second Onetime Secret client first.** Link creation is the
  secondary interaction, deliberately subordinate. A full-featured API
  client (receipts, burn, metadata browsing) is future scope at most.
