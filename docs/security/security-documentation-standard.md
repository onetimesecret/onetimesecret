# Security Documentation Standard

## Purpose

This standard separates public security evidence from the current work queue. It gives readers one
place to answer each question:

- **What needs action now?** [Active security risk register](active-risk-register.md)
- **Why was it reported?** A dated report in [audits](audits/)
- **Why was it closed?** [Resolution log](records/resolution-log.md)
- **Which risks were explicitly accepted?** [Accepted-risk exceptions](records/accepted-risk-exceptions.md)

## Document classes

| Class | Location | Purpose | Change policy |
|---|---|---|---|
| Active register | `active-risk-register.md` | Canonical list of current actionable risks. | Updated as risk state changes. |
| Audit | `audits/security-audit-YYYY-MM-DD.md` | Point-in-time evidence, scope, findings, and validation. | Historical after publication; allow only an erratum or a short status pointer. |
| Historical risk register | `risk-registers/risk-register-YYYY-MM-DD.md` | Point-in-time prioritization from an assessment. | Historical after publication; link to the active register for current status. |
| Resolution log | `records/resolution-log.md` | Verified closure record. | Append-only. |
| Accepted-risk exceptions | `records/accepted-risk-exceptions.md` | Explicit, time-bounded acceptance decisions. | Updated at acceptance, review, expiry, or withdrawal. |
| Assessment evidence | `assessments/` | Full assessment artifacts, raw outputs, proofs, and working notes. | Local/private and Git-ignored. Do not link public documents to it. |

## Status vocabulary

Use only these values in the active register:

- **Open** — remediation or an explicit acceptance decision is required.
- **Mitigating** — remediation is underway; the risk remains actionable.
- **Accepted** — an accountable owner has accepted the residual risk with a rationale,
  compensating controls, and a review or expiry date. Accepted risks remain visible in the active
  register and in the exceptions record.
- **Resolved** — the vulnerable condition is removed or otherwise fully addressed, and closure is
  verified at a named baseline.
- **Retired** — the reported condition was disproven or does not constitute a security risk.
- **Superseded** — a specific successor risk record replaces this one. Always name and link the
  successor; never use this label merely to stop tracking work.

**Carried forward** and **migrated** are historical-document dispositions, not active-risk
statuses. They mean that a dated report now points to the active register.

## Required active-register fields

Every active row must include:

1. A stable, globally unique ID, such as `RISK-2026-08-13-02`.
2. Status, priority, and risk rating.
3. A concise description of the security consequence.
4. A public source link to the dated audit or historical register.
5. A concrete next action or acceptance decision needed to change its status.

Add an owner, tracking issue, and target/review date when they are assigned. Record `Unassigned`
or `Not scheduled` rather than inventing them.

## Lifecycle

1. Publish a dated audit or historical assessment with the evidence available at its baseline.
2. Create a stable active-register entry for each actionable finding, or update the existing entry
   when it is the same risk.
3. Link the historical document to the active register. Do not use the historical document as a
   live work queue.
4. During remediation, keep the item `Open` or mark it `Mitigating`; retain source links and the
   original rating unless it is explicitly re-assessed.
5. Before marking `Resolved`, verify the fix and record the implementation reference, validation,
   closure date, and code baseline in the resolution log.
6. For a decision not to remediate, record an `Accepted` exception with a named decision owner,
   rationale, compensating controls, and expiry/review date. Re-open it when the exception expires
   or its assumptions change.
7. Use `Retired` only for a refuted/non-risk claim, and `Superseded` only with a named successor.

## Public/private boundary

Tracked `docs/security/` content is public-facing documentation: the README, active register,
standards, resolution/exception records, historical risk registers, and dated audits.

`docs/security/assessments/` is intentionally ignored. It may contain raw tool output, proofs of
concept, environment detail, or other material inappropriate for a public repository. Public
records must summarize the necessary evidence and link only to tracked public documentation,
commits, issues, or releases.

## Review cadence

Update the active register whenever a finding is published, remediated, accepted, retired, or
superseded. Revalidate open and accepted entries during each security review and after material
changes to their affected code or deployment assumptions.
