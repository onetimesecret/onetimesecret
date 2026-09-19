---
id: "048"
status: proposed
title: "ADR-048: Evidence Basis for Security Decisions"
---

## Status

Proposed

## Date

2026-09-18

## Context

Security-relevant behavior in this codebase is often decided at a point of
disagreement: a reviewer reads a change one way, a spec asserts another, and
the existing code does a third thing. When that happens the question "should
the behavior change, or the spec?" tends to be settled by whoever is present,
from preference or from recollection of what a standard says.

Both are unreliable. Preference varies by person and by day. Recollection is
worse than it feels: section numbers move between revisions (NIST SP 800-63B
revision 3 and revision 4 number their session requirements differently), and
a confidently remembered requirement may not say what it is remembered to say.
Work in this repository is also increasingly drafted by AI agents, which
produce plausible citations from memory with the same fluency as correct ones.

The repository already cites standards in places. For example,
`docs/authentication/per-install-sso.md` cites OWASP ASVS 5.0.0 requirement
7.5.1 and NIST SP 800-63C-4 section 3.8.1 for authenticated identity linking,
and distinguishes controls those standards require from OTS choices. That
practice is not yet recorded or applied consistently. In the same document, a
gap in the basis for ending a session before an SSO callback turned a stale
specification into a request for maintainer judgment.

“Follow best practices” cannot resolve a disagreement or be checked later. The
project needs a standard for the evidence that supports a security decision,
how to record it, and how to proceed when no standard applies.

## Decision

Security-relevant behavior that is introduced, changed, or defended in a
disagreement must be supported by a cited, verified source—or recorded as a
judgment when no applicable source exists—in the document that records the
behavior. It must not rest only on the preference or recollection of a
maintainer, reviewer, or agent.

### Scope

This decision applies to authentication; session management; federation and
identity linking; authorization and tenant isolation; cryptography and secret
handling; transport and browser security policy; and audit logging for those
areas. Outside this scope, it is advisory.

### Required evidence

1. **Cite the highest-authority applicable source, at a pinned version.** Name
   the document, version or revision, and section or requirement number, and
   link directly to it. For example: [OWASP ASVS 5.0.0 requirement
   7.4.2](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x16-V7-Session-Management.md#v74-session-termination),
   [RFC 9700 section 2.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1),
   or [NIST SP 800-63C-4 section
   3.8.1](https://pages.nist.gov/800-63-4/sp800-63c/Federation/#account-linking).
   “Industry best practice” and “OWASP recommends” are not citations.
2. **Verify the source text when writing.** Read the cited section and quote
   its operative sentence when it is short. A citation recalled from memory is
   a lead to verify, not evidence. Report an agent-provided citation that has
   not been verified as unverified.
3. **Distinguish the source requirement from the OTS control.** State what the
   source requires, then the control OTS uses to meet it. Label controls the
   source does not prescribe as OTS choices.
4. **Resolve a test/behavior conflict with the source.** Neither existing
   behavior nor an existing test is presumed correct. Update the test when the
   source supports the behavior; otherwise update the behavior. Record the
   source and outcome in the commit message.
5. **Record a judgment when no source applies.** State that no applicable
   source was found, the reasoning, and the threat addressed. Do not stretch a
   citation to cover the judgment. Use an ADR when the judgment establishes a
   pattern, is expensive to reverse, affects multiple components, or resolves
   a technical debate.
6. **Record deliberate deviations beside the citation.** When OTS knowingly
   does not meet a cited requirement—for example, because it does not target a
   level or accept a cost—state the deviation and reason.

### Source order

Use the following order to select among applicable sources:

1. The normative specification for the protocol or mechanism in use: IETF RFCs
   and BCPs, W3C and WHATWG specifications, OpenID Foundation specifications,
   or FIPS.
2. Government or standards-body guidance, including the NIST SP 800 series and
   ISO/IEC 27001 and 27002.
3. Consensus verification standards, including OWASP ASVS; OWASP Cheat Sheets
   may provide supporting detail.
4. Library documentation, such as Rodauth, OmniAuth, or ruby-saml, to describe
   library behavior rather than to establish what is correct.

Blog posts, forum answers, and vendor marketing may help locate a source, but
are not evidence for the decision.

### Where to record the evidence

Record the full argument in the durable feature document—for example,
`docs/authentication/`, `docs/security/`, or an ADR that meets the [ADR
criteria](README.md#when-to-write-an-adr). Summarize the source and outcome in
the commit message as required by [ADR-039](adr-039-issue-and-pull-request-references-in-change-metadata.md).
Source comments may name the standard and explain the local reason for the
behavior, but do not carry the full argument.

This decision does not require citations for routine, undisputed changes or
retroactively for existing code. It applies when security-relevant behavior is
introduced, changed, or defended against a challenge.

## Trade-offs

- **We lose**: Speed at the moment of decision. Reading the section takes
  longer than remembering it, and some decisions will wait on that reading.
  We also lose the freedom to settle a disagreement by seniority.
- **We gain**: Decisions that a later maintainer, auditor or customer
  security review can check without asking anyone, and that survive a change
  of maintainer. Disagreements end at a text both sides can read.
- **Risk**: Citation as ritual. A link that was never read satisfies the
  letter of this ADR and defeats its purpose; rule 2 is the defense and it is
  only as good as review. Standards also lag practice, conflict with each
  other, and are silent on most product-specific design. Rule 6 exists so
  that silence is recorded rather than papered over. Pinned versions go
  stale; a revision bump is a reason to re-read the cited sections, not to
  rewrite the links mechanically.

## Related

- [ADR-039: Issue and Pull Request References in Change Metadata](adr-039-issue-and-pull-request-references-in-change-metadata.md)
- [ADR-045: Prioritizing Work](adr-045-prioritizing-work.md), which applies the
  same evidence-based approach to planning decisions.
- [`docs/authentication/per-install-sso.md`](../authentication/per-install-sso.md),
  particularly [Connected Identities](../authentication/per-install-sso.md#connected-identities-authenticated-linking-from-account-settings)
  and [Sessions ended before the callback](../authentication/per-install-sso.md#sessions-ended-before-the-callback).
