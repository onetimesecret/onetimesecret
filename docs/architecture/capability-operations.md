# Capability checks in v0.27

Use the target organization when checking a member's authority. For example,
`require_feature_and_capability_in!(org, feature: :custom_domains, capability: :manage_domains)`
requires both the organization's feature and the member's capability. The
calling endpoint also checks the resource scope. A domain-scoped member may
have a capability in their organization while lacking access to a sibling
domain.

The paired gate checks authority before consulting the plan. A member who
lacks the capability gets `CapabilityRequired`. A missing feature produces
`EntitlementRequired` and can carry upgrade information. Either gate refuses
anonymous callers, inactive memberships and a missing target organization.
A verified site operator can pass the capability check without a membership.
The paired gate still checks the target organization's feature for that operator.

## Operations and integration owners

The owner in this table is the application that enforces the operation. The
tests name the behavior to preserve when migrating each caller.

| Application and operations | Effective checks in v0.27 | Integration and regression coverage |
| --- | --- | --- |
| Organizations API, invitations and organization updates | Invitations require `manage_members`, organization edits and member role changes require `manage_org`. Each action also applies its organization scope rules. | Keep the endpoint and the [account permission response](../../spec/api/account/get_permissions_spec.rb) in agreement. |
| Domains API, tenant SSO credentials | Active members need `manage_org`, `manage_sso` and access to the domain. The installation flag and the existing operator exception apply. | [Domain configuration policy](../../apps/api/domains/policies/domain_config_authorization.rb), [SSO policy](../../apps/api/domains/logic/sso_config/base.rb) and [HTTP comparison](../../spec/api/account/get_permissions_spec.rb). |
| Domains API, incoming settings | Target membership capability `manage_org`, domain scope, then organization feature `incoming_secrets`. The feature applies to operators too. A missing domain or wrong scope gets the same response. | [Incoming settings policy](../../apps/api/domains/logic/incoming_config/base.rb) and [scope and denial tests](../../apps/api/domains/spec/logic/incoming_config/i18n_error_keys_spec.rb). |
| Domains API, domain creation, listing, reading and removal | The existing member `custom_domains` entitlement combines the role tier, plan and member overrides. Listing filters domains by membership scope. Reading and removal check the target domain. | [Creation](../../spec/api/domains/add_domain_role_gate_spec.rb), [removal](../../spec/api/domains/remove_domain_role_gate_spec.rb) and [scope](../../spec/api/domains/domain_scope_enforcement_spec.rb). See the cutover conditions below. |
| Domains API, other domain settings | Configuration writes and settings endpoints check `manage_org`, the feature for the setting, any installation flag and domain scope. Brand/image reads use a role-scoped feature. Brand privacy and extended expiry edits have additional member feature checks. | Keep the [configuration policy](../../apps/api/domains/policies/domain_config_authorization.rb) and [domain-scope tests](../../spec/api/domains/domain_scope_enforcement_spec.rb) when migrating these routes. |
| Organizations API, organization details, member listing and secret activity | Details and members use the legacy target member's `api_access`. Activity uses the member's `audit_logs` and the action's scope checks. | Keep [organization logic](../../apps/api/organizations/logic) on the target membership bridge until member feature overrides, scope and verified-operator behavior are covered for each conversion. |
| Secret and receipt APIs | Existing `require_entitlement!` checks the request's selected membership. Secret actions use `api_access` and optional `extended_default_expiration`. Organization and domain receipt listings add `audit_logs` and a scope check. Guest routes have their own admission rules. | [Request-context gate tests](../../spec/unit/onetime/logic/require_entitlement_spec.rb) and [receipt scope tests](../../apps/api/v2/spec/logic/secrets/list_receipts_authorization_spec.rb). |
| Billing web app | The checkout and portal for an existing target require its owner. Invoices, changes of plan or currency, and subscription cancellation and reactivation also require ownership. The overview and subscription status use the billing controller's membership or ownership check. | [Controller](../../apps/web/billing/controllers/billing.rb) and [billing portal and checkout tests](../../apps/web/billing/spec/controllers/plans_controller_spec.rb). |

### Domain management cutover

The workspace's Add Domain navigation follows its existing visibility rules
until the Domains API defines authority for creation. The workspace account
page and organization switcher also retain their legacy `manage_orgs` hint.
The account layer owns that decision. A membership capability cannot
authorize creating an organization.

`manage_domains` defaults to admins and owners. The domain record endpoints
continue to use the target member's `custom_domains` during this release.
A member's explicit feature grant can currently admit that member, and a
member's explicit revoke can deny an admin whose organization has the feature.
These cases need a decision and corresponding migration before adopting the
paired gate. Creation also needs an explicit policy for domain-scoped actors
because it creates an organization resource. Verify each action's site-operator
and scope behavior alongside the member cases.

Settings that currently require `manage_org` keep that requirement. Admitting
admins through the default `manage_domains` at those endpoints would expand
access and requires separate approval.

### Billing ownership

`manage_billing` is available for membership policy. The billing controllers
continue to use ownership for billing authority. A grant to another member
leaves the portal inaccessible to them, and an owner can still open the
portal after a revoke. The portal can change payment methods and cancel the
subscription. A future operation that accepts delegated authority needs its
own scope and tests before adopting this capability.
