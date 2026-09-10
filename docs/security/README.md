# docs/security/README.md

---

# Security Documentation

This directory separates the current security work queue from the historical evidence that created
it. Start with the [active security risk register](active-risk-register.md) for every actionable
item.

## Public records

- [Active security risk register](active-risk-register.md) — canonical status of work that remains actionable.
- [Resolution log](records/resolution-log.md) — verified closures.
- [Accepted-risk exceptions](records/accepted-risk-exceptions.md) — explicit, time-bounded acceptance decisions.
- [Security documentation standard](security-documentation-standard.md) — status vocabulary, lifecycle, and public/private boundary.
- [Security audits](audits/) — dated, historical audit reports.
- [Historical risk registers](risk-registers/) — dated assessment prioritization.

## Private assessment evidence

`assessments/` is intentionally Git-ignored. It may contain raw scanner output, proofs of concept,
environment detail, and working notes. Do not link public records to that material. Publish the
necessary finding summary, status, and verification evidence through the public records above.

## Maintaining the record

Publish new evidence in a dated audit, then add or update the corresponding stable entry in the
active register. When a fix is verified, append a closure record. See the
[security documentation standard](security-documentation-standard.md) for the required fields and
status transitions.
