# Legacy Plans

This document captures information about historical plans that are no longer
part of the active billing catalog (`etc/billing.yaml`) but that some
customers may still hold via grandfathered subscriptions. These details are
kept here because `apps/web/billing/docs/plan-definitions.md` is regenerated
from the catalog and would otherwise drop legacy entries.

If you need to look up what entitlements or limits a grandfathered customer
has, check the active subscription's `planid` against the records below.

---

## Legacy Plan (`legacy_plan_v1`) ⚠️

**Status:** Legacy — grandfathered for existing customers.

**Grandfathered Until:** 2028-01-31

**Tier:** single_team
**Tenancy:** multi
**Region:** N/A

**Entitlements:**
- `create_secrets`
- `view_receipt`
- `custom_domains`
- `custom_branding`
- `custom_privacy_defaults`
- `homepage_secrets`
- `incoming_secrets`
- `custom_mail_sender`
- `api_access`
- `flexible_from_domain`

**Limits:**

| Resource | Limit | Notes |
|----------|-------|-------|
| organizations | 1 |  |
| members_per_team | 5 |  |
| custom_domains | ∞ (unlimited) |  |
| secret_lifetime | 2592000 | 30 days |
| secrets_per_day | ∞ (unlimited) |  |

Role-specific limits (`owners_per_team`, `admins_per_team`,
`regular_members_per_team`) are not configured for this plan. When
`materialized_limit_for` returns 0 for a missing key, invitations to
this plan's organizations may need a re-materialization run after
the role-specific limits feature ships — see PR #3255 for the
deploy sequence.
