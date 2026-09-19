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

The repository already cites standards in places, and does it well:
`docs/authentication/per-install-sso.md` links OWASP ASVS 5.0.0 7.5.1 and NIST
SP 800-63C-4 3.8.1 for authenticated identity linking, and states which
controls are OTS choices that those standards do not prescribe. That practice
is unrecorded and unevenly applied. The same document had no basis recorded
for what happens when a session is ended before an SSO callback, and that gap
is what turned a spec failure into a request for the maintainer's opinion.

"Follow best practices" is not a decision: it is non-contentious and cannot be
checked. What can be decided is the standard of evidence a security decision
must meet, how that evidence is recorded, and what happens when no standard
speaks.

## Decision

A decision that changes or defends security-relevant behavior rests on a
cited, verified source, recorded where the behavior is documented. It does not
rest on the preference of the maintainer, a reviewer, or an agent.

**Scope.** Authentication, session management, federation and identity
linking, authorization and tenant isolation, cryptography and secret handling,
transport and browser security policy, and the audit logging of those. Outside
this scope the ADR is advisory.

**1. Cite a primary source, pinned.** Name the document, its version or
revision, and the section or requirement number, with a link: `OWASP ASVS
5.0.0 requirement 7.4.2`, `RFC 9700 section 2.1`, `NIST SP 800-63B-4 section
3.1.3.1`. "Industry best practice" and "OWASP recommends" are not citations.

**2. Verify against the source text when writing.** Read the cited section at
the time the citation is written, and quote the operative sentence when it is
short. A citation from memory is a lead to check, not a basis. This applies to
people and to agents alike; an agent's unverified citation is reported as
unverified.

**3. Prefer sources in this order.**

1. The normative specification for the protocol or mechanism in use (IETF
   RFCs and BCPs, W3C and WHATWG specifications, OpenID Foundation
   specifications, FIPS).
2. Government and standards-body guidance (NIST SP 800 series, ISO/IEC 27001
   and 27002).
3. Consensus verification standards (OWASP ASVS, and OWASP Cheat Sheets as
   supporting detail).
4. Documentation of the library that implements the behavior (Rodauth,
   OmniAuth, ruby-saml), for what the library does, not for what is correct.

Blog posts, forum answers and vendor marketing can locate a primary source.
They are not cited as the basis.

**4. Separate what the source requires from what OTS chose.** A standard
rarely prescribes an architecture. State the requirement, then state the
control OTS uses to meet it, and mark additional controls as OTS choices. A
reader must be able to tell which parts a standard would let us change.

**5. When a test and the behavior disagree, the source decides.** Neither the
existing test nor the existing behavior is presumed correct. If the source
supports the behavior, the test changes; if it supports the test, the
behavior changes. The commit message records which, and why.

**6. When no source speaks, say so.** Record the decision as a judgment, with
the reasoning and the threat it answers. Do not stretch a citation to cover
it. A judgment that establishes a pattern or is expensive to reverse gets its
own ADR under the usual criteria.

**7. Deviations are allowed and recorded.** Where OTS knowingly does not meet
a requirement it cites (a level it does not target, a cost it does not
accept), the document says so next to the citation, with the reason.

**Where the record lives.** In the durable document for the feature
(`docs/authentication/`, `docs/security/`, an ADR when the README criteria are
met), and summarized in the commit message per ADR-039. Source comments
explain the local reason for the behavior and may name the standard; they do
not carry the full argument.

**What this does not require.** Citations for routine changes, for behavior
that no one disputes, or retroactively for existing code. The obligation
attaches when security-relevant behavior is introduced, changed, or defended
against a challenge.

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

- ADR-039: Issue and Pull Request References in Change Metadata.
- ADR-045: Prioritizing Work, which takes the same position on evidence for
  planning decisions.
- `docs/authentication/per-install-sso.md`, "Connected Identities" and
  "Sessions ended before the callback": the citation practice this ADR
  records, and the case that prompted it.

## Implementation Notes

### Prompting case (2026-09-18)

Four SSO Connect specs expected a hook-level refusal for a suspended customer,
while the auth router had begun destroying that session before the hook ran.
The first recommendation made was a preference, and the first citations
offered were from memory, one of them with a superseded section number. Read
against the sources (OWASP ASVS 5.0.0 7.4.1 and 7.4.2; RFC 9700 2.1 and 4.7.1;
RFC 6749 10.12), the behavior was correct and the specs were stale. The
recommendation reversed once the sources were read.
