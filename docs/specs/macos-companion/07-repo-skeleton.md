# docs/specs/macos-companion/07-repo-skeleton.md
---

# Repo Skeleton — Initialization Prescription

How to initialize the application repository, written before doing it.
This is a prescription, not implementation: executing it is the first act
of milestone 2. Everything here is chosen to be cheap now and hard to
retrofit later — the same logic as the accessibility commitments in doc 05.

## Ground rules

- **A new repository, not this one.** The companion is standalone-useful
  and independently versioned; it does not live in the web app's monorepo.
  Initialize as `onetimesecret/macos-companion` — a deliberately unbranded
  name, because the product name is unresolved (doc 06 §8) and GitHub
  renames redirect. The product name must appear only as a UI string and
  a bundle display name, never as an identifier (crate names, bundle id,
  repo name), so the eventual rename is a one-file change.
- **Public from the first commit.** An open-source companion has no
  private incubation period to leak secrets from — and starting public
  enforces the no-credentials-in-repo discipline from day one.
- **The spec moves in.** `docs/specs/macos-companion/` from this repo is
  imported as `docs/spec/` in the new one; the copy here is then replaced
  by a pointer. The spec belongs with the code it governs.

## Layout

```
macos-companion/
├── Cargo.toml               # virtual workspace, resolver = "3"
├── Cargo.lock               # committed — this is an application
├── rust-toolchain.toml      # pinned stable + rustfmt + clippy
├── rustfmt.toml
├── deny.toml                # cargo-deny: advisories + license allowlist
├── .editorconfig
├── .gitignore               # target/, .DS_Store, *.p12, *.provisionprofile
├── crates/
│   ├── core/                # cell store, TTL wheel, zeroizing buffers,
│   │                        #   secret-shape heuristics — no macOS deps
│   ├── ots-client/          # v3 API + auth strategy trait — no macOS deps
│   └── pasteboard/          # NSPasteboard adapter (objc2) — macOS-only
├── shell/                   # empty until ADR-0002 (the milestone-2 decision)
├── spikes/
│   ├── tauri-panel/         # the two-way spike, doc 05 — disposable
│   └── swift-panel/         #   by construction, excluded from workspace
├── docs/
│   ├── spec/                # imported from this repo
│   └── adr/
│       ├── template.md      # context / decision / eject triggers
│       └── 0001-rust-core-thin-shell.md
├── .github/
│   ├── workflows/ci.yml
│   └── ISSUE_TEMPLATE/      # bug + question only; no feature-farm forms
├── LICENSE                  # MIT, matching the parent project
├── README.md                # honest pre-alpha: "design-first, no releases"
├── SECURITY.md              # points at Onetime Secret's disclosure process
├── CONTRIBUTING.md
└── CHANGELOG.md             # Keep a Changelog, seeded with [Unreleased]
```

One refinement over the doc 05 diagram: the pasteboard adapter is its own
crate rather than a module of `core`. This keeps `core` and `ots-client`
free of macOS dependencies, so the crates that hold all the logic build
and test on cheap Linux CI runners — the macOS runner is reserved for
`pasteboard`, the shell, and eventually the frugality-budget assertions.

## Workspace manifest decisions

- **Edition 2024, `resolver = "3"`,** current stable pinned in
  `rust-toolchain.toml` (bump deliberately, not ambiently).
- **`[workspace.lints]`:** `clippy::all` + a curated pedantic subset at
  `deny`; `unsafe_code = "deny"` in `core` and `ots-client`. Only
  `pasteboard` (and later the shell glue) may write `unsafe`, so the FFI
  surface is auditable by crate boundary, not by grep.
- **`panic = "unwind"` in release, on purpose.** `panic = "abort"` is the
  usual size win, but aborting skips `Drop` — and zeroize-on-drop *is* the
  security posture (doc 05). Unwinding panics scrub buffers on the way
  down. Record this in the manifest as a comment so nobody "optimizes" it
  away.
- **Release profile:** `lto = "thin"`, `strip = "symbols"`,
  `opt-level = "s"` as the starting point for the <10 MB budget.
- **Dependencies at init: `zeroize` in `core`. Nothing else.** Every
  further dependency arrives with the code that needs it; the skeleton
  ships no speculative deps. `cargo-deny` gates from commit one:
  advisories deny, licenses allowlisted to permissive
  (MIT/Apache-2.0/BSD/ISC/Zlib) so distribution stays simple.

`ots-client` is written as if it will be published to crates.io someday
(a general Rust client for the v3 API is independently useful); `core`
and `pasteboard` are `publish = false`.

## CI from the first push

Two lanes in one workflow, both required:

| Lane | Runner | Jobs |
| --- | --- | --- |
| Logic | `ubuntu-latest` | `fmt --check`, `clippy -D warnings`, `test -p core -p ots-client`, `cargo-deny` |
| Platform | `macos-latest` (arm64) | full-workspace clippy + test, incl. `pasteboard` |

Not in CI at init, recorded as future jobs in the workflow file as
comments: signing/notarization (a release-engineering ADR of its own) and
the frugality-budget assertions from doc 05, which become measurable only
once a binary exists.

## Governance files

- **LICENSE:** MIT, same as the parent project.
- **SECURITY.md:** no parallel process — point at Onetime Secret's
  existing disclosure channel, with a note that memory-hygiene claims
  (doc 05) are explicitly in scope for reports.
- **CONTRIBUTING.md:** short. Spec-first (changes to behaviour start in
  `docs/spec/`), decisions land as ADRs, anti-goals (doc 01) are the
  review bar for feature PRs.
- **README.md:** states plainly that this is a design-first project with
  no releases yet, links the spec's reading order, and repeats the
  one-paragraph summary. No screenshots of vaporware.

## ADR practice, seeded

`docs/adr/template.md` carries four sections: context, decision,
consequences, **eject triggers** — the observable conditions under which
the decision gets revisited. Two ADRs exist at init:

- **ADR-0001, accepted:** UI-agnostic Rust core + thin shell (doc 05's
  architecture shape) — the one decision milestone 1 actually made.
- **ADR-0002, proposed & empty:** shell selection. Filled in only after
  the two-way panel spike; `spikes/` exists so the evidence has a home
  that is visibly not product code.

## Identifiers reserved at init

- Bundle id placeholder: `com.onetimesecret.companion` (safe to change
  any time before first notarized release, painful after).
- Crate names: `companion-core`, `companion-pasteboard`, `ots-client`.
- No trademark-sensitive strings ("Airlock" or successors) anywhere but
  `README.md`'s naming note.

## Definition of done

The skeleton is initialized when:

1. `cargo test` passes on a Linux machine with no macOS SDK present.
2. CI is green on both lanes with zero warnings.
3. `cargo deny check` passes.
4. The repo contains no binary assets, no signing material, and no
   credentials — verified by eyeball and by `.gitignore` before the
   first push, not after.
5. Both ADR files exist; ADR-0002 is honestly empty.
6. `README.md` would not embarrass anyone if linked from Hacker News an
   hour after the push.
