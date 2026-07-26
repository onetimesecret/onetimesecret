# Review Rules

Skip findings you cannot state as a concrete failure scenario in the changed
lines. Do not comment on style, naming, formatting, docs wording, test
organization, or locale content hashes; linters and CI gates cover those. Do
not flag pre-existing code as introduced by this PR.

If a finding depends on an invariant outside the diff (transaction
boundaries, session key lifecycles, OAuth state handling), ask a question
rather than asserting a P1 — unless this PR modifies the mechanism that
enforces the invariant, in which case the invariant is in scope and must be
reviewed. See `AGENTS.md` for the invariant list.

Structural or architectural observations that lack a failure scenario may be
raised as explicitly non-blocking follow-up suggestions, at most two per
review.
