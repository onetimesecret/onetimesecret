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

Security-relevant behavior in this codebase is often decided amid conflicting
claims: a reviewer interprets a change one way, a test asserts another, and
the existing code does something else. In that situation, the question
“should the behavior change, or should the test change?”
can be settled by whoever is present, based on preference or memory.

Neither is reliable. Preferences vary. Recalled requirements may come from a
different revision or may not say what the author remembers. For example,
NIST SP 800-63B revisions 3 and 4 number their session requirements
differently. AI agents create an additional risk because they can produce
plausible but incorrect citations as fluently as correct ones.

The repository already demonstrates a better practice.
[`docs/authentication/per-install-sso.md`](../authentication/per-install-sso.md)
cites OWASP ASVS 5.0.0 requirement 7.5.1 and NIST SP 800-63C-4 section 3.8.1
for authenticated identity linking. It also distinguishes requirements in
those sources from additional controls chosen by Onetime Secret (OTS).
However, this practice is not recorded and is applied unevenly. The same
document originally gave no basis for its behavior when a session ends before
an SSO callback. That omission turned a test failure into a request
for the maintainer’s opinion.

“Follow best practices” is not a decision because it cannot be checked. The
project instead needs a standard for what evidence supports a security
decision, how to record that evidence, and what to do when authoritative
sources are silent or allow more than one design.

## Decision

A decision that introduces, changes, or defends security-relevant behavior
must rely on verified evidence recorded in the durable documentation for that
behavior. It must not rely only on the preference or memory of a maintainer,
reviewer, or agent.

### Scope

This requirement applies to decisions about:

- authentication and session management;
- federation and identity linking;
- authorization and tenant isolation;
- cryptography and secret handling;
- transport and browser security policy; and
- security audit logging for those areas.

Outside this scope, the ADR is advisory.

### Evidence requirements

1. **Cite a versioned primary source.** Name the document, version or revision,
   and section or requirement number, and provide a link. Examples include
   [OWASP ASVS 5.0.0 requirement 7.4.2](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x16-V7-Session-Management.md#v74-session-termination),
   [RFC 9700 section 2.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1),
   and [NIST SP 800-63C-4 section 3.8.1](https://pages.nist.gov/800-63-4/sp800-63c/Federation/#account-linking).
   Phrases such as “industry best practice” and “OWASP recommends” are not
   citations.

2. **Verify the citation against the source text.** Read the cited section when
   writing the decision. Record the operative sentence with a direct or
   section-level link. If the source cannot be excerpted, record its edition
   and exact clause number instead. Put this evidence in the durable feature
   document or commit message; a chat transcript alone is not a durable
   record. A citation recalled from memory, or retrieved without this
   checkable record, remains unverified. This rule applies equally to people
   and agents.

3. **Prefer sources in this order:**

   1. the normative specification for the protocol or mechanism in use,
      including IETF RFCs and BCPs, W3C and WHATWG specifications, OpenID
      Foundation specifications, and FIPS publications;
   2. government and standards-body guidance, including the NIST SP 800 series
      and ISO/IEC 27001 and 27002;
   3. consensus verification standards, including OWASP ASVS, with OWASP Cheat
      Sheets as supporting guidance; and
   4. documentation for the library that implements the behavior, such as
      Rodauth, OmniAuth, or `ruby-saml`, as evidence of what the library does
      rather than what the security design should be.

   Blog posts, forum answers, and vendor marketing may help locate a primary
   source, but they are not the basis for the decision.

4. **Separate source requirements from OTS choices.** A standard rarely
   prescribes a complete architecture. State what the source requires, then
   state how OTS meets that requirement. Identify additional controls as OTS
   choices so readers can tell which parts may change without violating the
   cited requirement.

5. **Use the evidence to resolve disagreements between tests and behavior.**
   Do not presume that either the existing test or the existing behavior is
   correct. If the applicable sources require one outcome, change the side
   that conflicts with that outcome. If the sources allow both outcomes or
   conflict with one another, apply rule 6. Summarize the result and rationale
   in the commit message.

6. **Record judgments when sources do not determine the answer.** If no
   authoritative source addresses the case, or the applicable sources permit
   multiple designs, say so. Record the chosen behavior, its reasoning, and
   the threat or failure it addresses. Do not stretch a citation beyond what
   it supports. A judgment that establishes a pattern or is expensive to
   reverse receives its own ADR under the
   [ADR criteria](README.md#when-to-write-an-adr).

7. **Record deliberate deviations.** If OTS knowingly does not meet a cited
   requirement—for example, because the project does not target that assurance
   level—state the deviation and its reason next to the citation.

### Where to record the evidence

Record the full argument in the durable document for the feature, such as a
page under `docs/authentication/` or `docs/security/`, or in an ADR when the
[ADR criteria](README.md#when-to-write-an-adr) apply. Summarize the decision in
the commit message as required by
[ADR-039](adr-039-issue-and-pull-request-references-in-change-metadata.md).

Source comments may identify the relevant standard, but their primary purpose
is to explain the local, enduring reason for the behavior. They do not carry
the full argument.

### Applicability to existing and routine work

This ADR does not require retroactive citations for existing code. It also
does not require a new citation for routine implementation work that neither
establishes nor changes a security decision already documented elsewhere.

The obligation begins when scoped behavior is introduced or changed, or when
an existing behavior is challenged and must be defended. A routine change may
refer to an existing evidence record instead of repeating it.

## Trade-offs

- **We lose:** Speed at the moment of decision. Reading the relevant source
  takes longer than relying on memory, and some decisions will wait for that
  verification. Seniority alone does not settle a disagreement; when sources
  do not determine the answer, rule 6 requires a recorded judgment.
- **We gain:** Decisions that later maintainers, auditors, and customer
  security reviewers can verify without asking the original author. A shared
  source also gives disagreements a checkable basis.
- **Risk:** Citation can become ritual. An unread link satisfies the form of
  this ADR while defeating its purpose; rule 2 is the defense, and review must
  enforce it. Standards may also lag practice, conflict, or remain silent on
  product-specific design. Rule 6 requires the project to record that
  uncertainty rather than conceal it. Pinned versions eventually become
  outdated; adopting a new revision requires re-reading the cited sections,
  not mechanically updating links.

## Related

- [ADR-039: Issue and Pull Request References in Change Metadata](adr-039-issue-and-pull-request-references-in-change-metadata.md)
- [ADR-045: Prioritizing Work](adr-045-prioritizing-work.md), which takes a
  similar evidence-based approach to planning decisions
- [`docs/authentication/per-install-sso.md`](../authentication/per-install-sso.md),
  especially [“Connected Identities”](../authentication/per-install-sso.md#connected-identities-authenticated-linking-from-account-settings)
  and [“Sessions ended before the callback”](../authentication/per-install-sso.md#sessions-ended-before-the-callback),
  which demonstrate the citation practice and document the case that prompted
  this ADR

## Implementation Notes

### Prompting case (2026-09-18)

Four SSO Connect RSpec examples expected a hook-level refusal for a suspended
customer, while the authentication router had begun destroying the session
before the hook ran. The first recommendation expressed a preference. The
first citations were recalled from memory, and one used a superseded section
number.

Reading [OWASP ASVS 5.0.0 requirements 7.4.1 and 7.4.2](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x16-V7-Session-Management.md#v74-session-termination),
[RFC 9700 sections 2.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1)
and [4.7.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.7.1), and
[RFC 6749 section 10.12](https://www.rfc-editor.org/rfc/rfc6749#section-10.12)
showed that the behavior was supported and the RSpec examples were stale. The
recommendation changed after the sources were verified.
