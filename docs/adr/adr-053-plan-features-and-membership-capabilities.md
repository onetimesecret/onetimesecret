---
id: "053"
status: accepted
title: "ADR-053: Plan features and membership capabilities"
---

## Status

Accepted with the v0.27.0 foundation merge. Supersedes the authorization
model proposed in [ADR-012](adr-012-membership-level-entitlements.md).

## Date

2026-11-23

## Context

A subscription can include custom domains while an individual member lacks
authority to administer them. Existing clients and endpoints use an entitlement
list that also encodes role tiers and individual exceptions. Reinterpreting
that list would change access during an upgrade or rollback.

## Decision

The organization owns plan features and numeric limits. An active membership
owns role capabilities. A plan change can affect feature availability. A role
change, membership removal, or individual capability override can affect
member authority. A capability revoke takes precedence over a grant. The same
role defaults apply with billing enabled and in standalone installations.

The [registry](../../src/schemas/contracts/authorization-registry.json) assigns
each identifier a kind. `audit_logs` and `api_access` identify subscription
features. Their existing endpoints retain any role, credential, or resource
checks they already perform. `manage_orgs` belongs to the account layer.
`manage_teams` is reserved. Neither identifier gives a membership authority.
`manage_domains` defaults to admins and owners. The billing portal checks
ownership independently of `manage_billing`.

New organization operations specify both dimensions together when they need
a feature and a capability. Resource policies separately check membership
status, organization identity, domain scope, and any action-specific rules.
Workspace controls use server decisions for the requested resource.
Anonymous access and site-operator exceptions require an explicit endpoint
policy. The legacy secret and receipt flows retain their existing rules.

New readers use `plan_entitlements` and `role_capabilities`. An explicitly
empty array is authoritative. During the compatibility window the server also
maintains the old fields and override behavior. Member feature exceptions
remain scoped to their existing membership. Assigning one to the organization
would change access for its other members.

Before converting an endpoint, compare decisions on both sides of the change
for existing role tiers, individual grants and revokes, plan state, domain
scope, missing or inactive memberships, and applicable operator exceptions.
An operation that would admit additional callers requires an explicit operator
decision. The [operation inventory](../architecture/capability-operations.md)
tracks the remaining consumers.
