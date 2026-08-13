---
id: 036
status: accepted
decided: 2026-08-13
title: 'ADR-036: ADRs Are Living Documents; Git Is the History'
---

<!-- adr-lint: ignore-file — cites ADR numbers illustratively -->

# ADR-036: ADRs Are Living Documents; Git Is the History

## Context

Nygard's format assumes documents are immutable once accepted. A decision that
changes is not edited; a new ADR supersedes the old one, and readers follow the
supersession chain to reach current truth. That assumption is what makes
references durable — `ADR-024 §3` stays valid forever because ADR-024 never
changes, the same way RFC section numbers stay valid because RFCs are frozen at
publication.

We are optimizing for something else. Within one team and one codebase the
question people ask is "what do we do today," not "what did we believe in
2024." A supersession chain answers the second question well and the first
badly: current truth is assembled by reading N documents in order and mentally
applying diffs, a cost paid on every read, by everyone, forever.

We already have a system that answers "what did we believe in 2024": git. It is
better at it than a supersession chain, having timestamps, authors, diffs, and
the code change that accompanied the decision.

So we invert the tradeoff. ADRs are mutable and always describe current truth.
History moves to git.

This has one real cost, and it is the reason this ADR exists: mutable documents
break positional references. Sequence labels (`A1`, `A2`, `§3.2`) assigned by
document order are stable only until someone reorders, splits, or merges
sections — which under a living-document model is a routine Tuesday. Every rule
below exists so that references survive editing.

## Decision

**ADRs are edited in place to reflect current truth. References into them are
content-addressed via declared anchors, never positional. Git is the historical
record.**

### ADR numbers are permanent {#adr-numbers-are-permanent}

A number is assigned at merge and never reused, even if the ADR is retired or
its content moves elsewhere. `ADR-024` refers to one document for the life of
the repository. The `id` in frontmatter is authoritative; the filename slug is
descriptive and may be renamed freely, because nothing cites it.

### Documents are edited in place {#documents-are-edited-in-place}

When a decision changes, edit the ADR. No amendment sections, no changelog, no
revision table, no dated "as of 2026-08 this now says" notes. Those reintroduce
the assembly cost this format exists to remove.

The document reads as if it had always said what it now says. Anyone who needs
to know what changed runs `git log -p` on the file.

### Anchors are declared, not derived {#anchors-are-declared}

A citable clause declares its own anchor on the heading line:

```markdown
### Nil clears restriction {#nil-clears-restriction}
```

The anchor is a token in the file, not a function of the heading text and not a
product of any renderer. Consequences, all of them good:

- Heading text is free to edit. Rewording a heading for clarity breaks nothing.
- Reordering, splitting, and merging sections break nothing.
- A reference is greppable and machine-checkable regardless of how or whether
  the markdown is ever rendered.

Anchors are never reused for different content and never renamed without a
codebase sweep in the same commit. A section with no declared anchor is simply
not citable, which is the correct default — most sections aren't.

Never assign sequence labels. No `A1`, `A2`, no clause numbers that anything
outside the document refers to. Numbered lists are fine for reading; they are
not addresses.

### Moving a decision leaves a forwarding anchor {#moving-leaves-a-forwarding-anchor}

When content moves to another ADR, leave the anchor in place in the old
document with a single line of body:

```markdown
### Nil clears restriction {#nil-clears-restriction}

Moved to ADR-035#nil-clears-restriction.
```

This is the only bookkeeping the format requires, and it is required because it
is the one failure git cannot fix: a dangling `ADR-024#foo` in a code comment
points at nothing while reading as though it points at something. The
forwarding anchor keeps existing references resolvable and gives the linter
something to verify.

Delete a forwarding anchor once no reference to it remains.

### Status is proposed, accepted, or retired {#status-values}

Status lives in frontmatter and nowhere else.

- **proposed** — open for discussion, not yet binding.
- **accepted** — current truth. The overwhelming majority of ADRs.
- **retired** — the decision no longer applies and was not replaced by another
  ADR: the technology was removed, the problem stopped existing. A one-line
  `retired:` note in frontmatter says why. The body is left as-is; git has the
  rest.

There is no **superseded** and no **deprecated**. A decision that changes is an
edit. A decision whose scope moves to another ADR uses forwarding anchors.
Retired ADRs keep their anchors resolvable.

### Code comments cite, they do not restate {#code-comments-cite}

```ruby
# ADR-024#nil-clears-restriction
def clear_restriction!
```

One line, no summary of the decision. A restated decision in a comment is a
second copy that drifts silently; a citation stays correct because the ADR is
maintained and the linter proves the anchor exists.

Cite the narrowest anchor covering the code. Cite a bare `ADR-024` only when
the whole document is the point.

### CI enforces that references resolve {#ci-enforces-references}

`bin/adr-lint` extracts every `ADR-NNN#slug` in the repository — code, docs,
and ADRs — and fails if the document or the declared anchor does not exist. It
runs on every push. When a heading matches but declares no anchor, the error
says so, because that is the common mistake.

Without this the format degrades into a convention nobody notices breaking.
With it, breaking a reference fails the build in the commit that broke it,
which is the only moment the fix is cheap.

Documents that cite ADR numbers illustratively — this one, design sketches,
drafts — opt out with `<!-- adr-lint: ignore-file -->`, or per line with a
trailing `adr-lint:ignore`. Fenced code blocks in markdown are skipped.

### Git carries the history {#git-carries-history}

For git to substitute for supersession chains it has to be legible:

- ADR edits go in their own commit, separate from the code implementing them,
  so `git log -- docs/adr/adr-024-*.md` is a decision log and not a code log.
- Commit subject `adr(024): <what changed>`; body says why, in a sentence or
  three. This is the text that replaces the amendment section.
- Never force-push over ADR history on the default branch.
- Reference the implementing PR in the commit body when there is one.

### Frontmatter carries the metadata {#frontmatter-metadata}

`id`, `status`, `decided`, `title`. Nothing else, and no duplicate `## Status`
or `## Date` section in the body — two copies of a fact is one copy too many.

`decided` is the date the decision was first accepted and does not change when
the document is edited. There is deliberately no `updated` field: git owns
that, and a hand-maintained one drifts.

## Consequences

### Positive

- Reading an ADR gives current truth. No chain to walk, no diffs to apply
  mentally.
- References survive reordering, splitting, merging, and rewording, all of
  which are routine under this model.
- One decision keeps one number for its life, so code comments, search, and
  conversation converge on the same identifier.
- Dangling references become build failures rather than slow rot.
- No parallel history to maintain, and so no parallel history to fall out of
  sync with git.

### Negative

- Point-in-time reconstruction requires git. "What did our policy say when this
  incident happened" is `git log --before`, not scrolling. Fine inside a team;
  not fine for a published standard or any document with external consumers.
- The commit-message convention is load-bearing and unenforceable by tooling. A
  lazy `adr(024): update` destroys the rationale an amendment section would
  have preserved.
- Declared anchors are visible in the raw markdown, which is mild noise.
- Forwarding anchors accumulate in older ADRs until someone prunes them.

### Neutral

- Reviewing an ADR change means reviewing a diff rather than a new document. A
  different reviewing skill, not obviously better or worse.
- This format suits internal, single-repository decisions. Anything published
  outside the team should use immutable Nygard with supersession.

## Rollout

Existing ADRs are not rewritten. Convert opportunistically:

1. When an ADR is next edited, fold any amendment or dated implementation notes
   into the body as current truth, and delete the sections.
2. Move `## Status` / `## Date` into frontmatter; map `deprecated` and
   `superseded` onto `retired`, or onto an edit where the decision actually
   changed.
3. Replace sequence labels with declared anchors and sweep the citing comments
   in the same commit.
4. ADR-024 → ADR-034/035: add a forwarding anchor in ADR-024 for every old
   label code still cites, pointing at the new anchors, then sweep the ~20
   comments. The linter goes green there and stays green.

Delete this section when the conversion is done.

## References

- Nygard, M. "Documenting Architecture Decisions" — the immutable original
- `bin/adr-lint`
- ADR-000 — template
