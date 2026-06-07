# Organization Membership Entitlements

This document describes how organization membership entitlements are materialized in Onetime Secret when both `ENABLE_ORGS=true` and `ENABLE_SSO=true` are active.

## Overview

Organization membership entitlements dictate what actions a user can perform within a specific organization context.

When a user joins an organization, their entitlements are materialized as the intersection of the organization's plan-level entitlements and the user's role constraints (`ROLE_ENTITLEMENTS[role]`). This ensures a membership never exceeds its organization's plan, while role templates restrict which plan entitlements the specific role permits.

Regardless of how a user joins (via an email invite or JIT SSO provisioning), both codepaths converge on the `OrganizationMembership` model and call `materialize_for_role!` to persistently materialize entitlements.

## Provisioning Codepaths

### 1. Email Invitation (`invite`)

When a user clicks an invite link and signs up or logs in, the flow is:

1. **Signup/Login Hook:** `apps/web/auth/config/hooks/account.rb` sets the customer's `provisioning_origin = 'invite'` and auto-verifies the account since they own the email address.
2. **Acceptance API:** The frontend makes a POST request to `/api/invite/:token/accept`, which invokes `InviteAPI::Logic::Invites::AcceptInvite`.
3. **Invitation Acceptance:** The logic calls `invitation.accept!(customer, provisioning_source: 'invited')`.
4. **Activation & Materialization:** Inside `OrganizationMembership#accept!`, the system validates the email, consumes the token, and calls `activate!`. This creates the active membership (via `organization.activate_members_instance`) and immediately calls `activated.materialize_for_role!` to persist the role-scoped entitlements in Redis.

### 2. JIT SSO Provisioning (`sso_jit`)

When a user logs into a custom domain via an Identity Provider, the flow is:

1. **OmniAuth Callback Hook:** `apps/web/auth/config/hooks/omniauth.rb` handles successful IdP authentication, creating the customer with `provisioning_origin: 'sso_jit'`.
2. **Domain Join Operation:** The hook invokes `Auth::Operations::JoinDomainOrganization#call`, which is responsible for ensuring the authenticated user is attached to the domain's primary organization.
3. **Ensure Membership:** The operation calls `Onetime::OrganizationMembership.ensure_membership(..., provisioning_source: 'sso')`.
4. **Direct Addition & Materialization:** If the user is not already a member, `ensure_membership` bypasses the invite token flow, directly creates the membership via `organization.add_members_instance`, and immediately invokes `membership.materialize_for_role!` to assign the corresponding entitlements.

## Architecture

```mermaid
sequenceDiagram
    participant U as User
    participant Hook as Auth Hook (account/omniauth)
    participant API as API / Operation
    participant OM as OrganizationMembership
    participant Org as Organization

    Note over U, Org: Flow 1: Email Invitation
    U->>Hook: Signup with invite_token
    Hook->>Hook: set provisioning_origin = 'invite'
    U->>API: POST /api/invite/:token/accept
    API->>OM: invitation.accept!(..., provisioning_source: 'invited')
    OM->>OM: Validate token & email
    OM->>OM: activate!()
    OM->>Org: activate_members_instance()
    Org-->>OM: activated_membership
    OM:::accent1->>OM:::accent1: activated.materialize_for_role!()
    Note right of OM: Materializes entitlements:<br/> Org Plan ∩ Role Template

    Note over U, Org: Flow 2: SSO JIT Provisioning
    U->>Hook: Authenticate via IdP (OmniAuth)
    Hook->>Hook: set provisioning_origin = 'sso_jit'
    Hook->>API: JoinDomainOrganization.call(customer)
    API->>OM: ensure_membership(..., provisioning_source: 'sso')
    OM->>Org: member?(customer)
    alt Not a member
        OM->>Org: add_members_instance()
        Org-->>OM: active_membership
        OM:::accent1->>OM:::accent1: membership.materialize_for_role!()
        Note right of OM: Materializes entitlements:<br/> Org Plan ∩ Role Template
    end
```
