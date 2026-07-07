# docs/specs/macos-companion/README.md
---

# macOS Companion — Design Spec

An open-source, Rust-based macOS desktop companion to Onetime Secret.
Working title: **Airlock** (see naming note below). Its cells of pasted
content are called **SleeperCells**.

This is a *design* spec, produced ahead of any implementation. Milestone 1
is deliberately narrow: restate the problem space in our own words, and map
the opportunities that neighbouring applications overlook. Interaction and
technical direction documents are included as supporting material — they
record current thinking, not decisions.

## One-paragraph summary

A menu-bar-resident staging area for content in transition. Drag or paste
text and images into a small edge-docked panel; each item becomes a
SleeperCell with a visible, limited time-to-live. Cells exist to be copied
back out and then forgotten — like a CPU's L1/L2 cache, the value is in
being small, close, and evicted by policy, never in being a system of
record. Secondarily, any cell can be promoted into a Onetime Secret link
(v3 API) when the content needs to travel to another person or machine.

## Reading order

| Doc | Contents | Milestone-1 status |
| --- | --- | --- |
| [01-problem-space.md](01-problem-space.md) | Restatement of the problem, the cache analogy taken seriously, anti-goals | **Core deliverable** |
| [02-overlooked-opportunities.md](02-overlooked-opportunities.md) | Landscape of neighbouring apps and the gaps they leave | **Core deliverable** |
| [03-design-principles.md](03-design-principles.md) | The principles that fall out of 01 + 02 | Supporting |
| [04-interaction-model.md](04-interaction-model.md) | SleeperCell anatomy, TTL cycling, panel behaviour, promotion flow | Supporting — draft |
| [05-technical-direction.md](05-technical-direction.md) | Rust framework survey, v3 API integration, security posture, a11y | Supporting — draft, no decisions |
| [06-open-questions.md](06-open-questions.md) | Everything unresolved, honestly | Supporting |
| [07-repo-skeleton.md](07-repo-skeleton.md) | Prescription for initializing the app repository | Supporting — prescription, not yet executed |

## Naming note

**Airlock** is a working title only: a small chamber between two
environments that things pass through but never live in — which is the
product in one image. It collides with at least one existing security
vendor (Airlock Digital), so it will not survive to release without a
trademark check. Alternatives considered: Layover, Vestibule, Foyer,
Waypoint, Holdover. The name matters less than the metaphor; every
candidate is a word for *a place you pass through*.

## Relationship to the web application

The companion is open source and standalone-useful: the core loop (paste,
hold briefly, copy out, forget) requires no account and no network. The
Onetime Secret v3 API appears only at the promotion step — turning a local
ephemeral cell into a one-time link. Authentication starts with HTTP Basic
(organization `extid` + API token pair) and migrates to PASETO when the v3
auth work lands. See [05-technical-direction.md](05-technical-direction.md).
