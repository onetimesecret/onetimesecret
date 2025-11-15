# Billing Data Model & Entity Relationships

**Version:** 1.0
**Date:** 2025-11-09
**Status:** Proposed Architecture

---

## Executive Summary

This document defines a comprehensive multi-tenant billing data model for OneTimeSecret, establishing clear separation between **identity** (users), **billing** (organizations), **access control** (teams/roles), and **entitlements** (subscriptions/plans).

### Key Design Decisions

1. **Organizations are billing entities** - Subscriptions attach to Organizations, not Users
2. **Users exist independently** - Users can belong to multiple Organizations
3. **Teams provide RBAC within Organizations** - Fine-grained permission control
4. **Seats track billing consumption** - Members are billable seats within Organizations
5. **Subscriptions grant entitlements** - Plans define capabilities, not roles

---

## 1. Core Entities

### 1.1 User (Identity)

**Purpose:** Individual identity across the entire system. Users exist independently of any organization.

```ruby
class User
  # Identity
  field :userid           # Primary key (UUID or similar)
  field :email            # Email address (unique)
  field :email_verified   # Verification status
  field :passphrase       # Password hash (via mixin)

  # Profile
  field :display_name     # Human-friendly name
  field :avatar_url       # Profile image
  field :locale           # Preferred language

  # Authentication
  field :apitoken         # Personal API token (for user-scoped actions)
  field :last_login       # Last login timestamp
  field :mfa_enabled      # Multi-factor auth status
  field :mfa_secret       # TOTP secret (encrypted)

  # Metadata
  field :created          # Account creation
  field :updated          # Last modified
  field :deleted_at       # Soft delete timestamp
  field :contributor      # Contributor flag

  # Relationships
  has_many :memberships   # User -> Organization memberships
  has_many :sessions      # Active sessions
  has_many :user_secrets  # Personal secrets (non-org)
end
```

**Redis Keys:**
- `user:{userid}:object` - User data hash
- `user:email:{email}:userid` - Email → userid lookup
- `user:{userid}:memberships` - Sorted set of organization IDs
- `onetime:user:values` - Sorted set of all users by created timestamp

**Key Principles:**
- Users can exist without any organization (personal account)
- Users can belong to multiple organizations
- Email is unique across all users
- Soft deletion preserves audit trail

---

### 1.2 Organization (Billing Entity)

**Purpose:** Container for billing, subscription, and resource ownership. The primary multi-tenant boundary.

```ruby
class Organization
  # Identity
  field :orgid            # Primary key (UUID)
  field :name             # Organization name
  field :slug             # URL-friendly identifier (unique)
  field :display_name     # Branded name

  # Billing
  field :stripe_customer_id     # Stripe Customer ID
  field :billing_email          # Billing contact email
  field :tax_id                 # Tax/VAT number
  field :billing_address        # JSON: { line1, city, country, postal_code }

  # Subscription (current active)
  field :subscription_id        # Current Stripe Subscription ID
  field :plan_id                # Current plan (anonymous, basic, identity, team, enterprise)
  field :billing_cycle          # 'month' or 'year'
  field :subscription_status    # active, trialing, past_due, canceled, etc.
  field :current_period_start   # Billing period start
  field :current_period_end     # Billing period end
  field :trial_end              # Trial expiration (if applicable)

  # Seat Management
  field :licensed_seats         # Number of paid seats
  field :consumed_seats         # Number of active members (calculated)
  field :seat_assignment_mode   # 'auto' or 'manual' (for seat control)

  # Settings
  field :settings               # JSON: org-level preferences
  field :branding               # JSON: { logo_url, icon_url, primary_color }
  field :allowed_email_domains  # Array: domains for auto-join
  field :require_mfa            # Enforce MFA for all members

  # Ownership
  field :owner_userid           # Primary owner (User.userid)
  field :created_by             # User who created org

  # Metadata
  field :created
  field :updated
  field :deleted_at             # Soft delete
  field :verified               # Org verification status

  # Relationships
  has_many :memberships         # Organization members
  has_many :teams               # Teams within org
  has_many :subscriptions       # Historical subscriptions
  has_many :custom_domains      # Owned domains
  has_many :secrets             # Org-scoped secrets
  has_many :invitations         # Pending invites
end
```

**Redis Keys:**
- `organization:{orgid}:object` - Org data hash
- `organization:slug:{slug}:orgid` - Slug → orgid lookup
- `organization:{orgid}:memberships` - Sorted set of membership IDs
- `organization:{orgid}:teams` - Sorted set of team IDs
- `organization:{orgid}:domains` - Set of custom domain IDs
- `onetime:organization:values` - Sorted set of all orgs

**Key Principles:**
- Organizations own subscriptions (not users)
- One active subscription per organization
- Billing happens at organization level
- Seats are managed per organization
- Each organization has exactly one owner

---

### 1.3 Membership (User ↔ Organization Junction)

**Purpose:** Represents a user's relationship with an organization, including their role and seat status.

```ruby
class Membership
  # Identity
  field :membershipid     # Primary key (UUID)
  field :orgid            # Organization ID
  field :userid           # User ID

  # Role & Permissions
  field :role             # org_owner, org_admin, org_member, org_billing, org_viewer
  field :team_ids         # Array of team IDs user belongs to

  # Seat Management
  field :consumes_seat    # Boolean: does this membership consume a billable seat?
  field :seat_assigned_at # When seat was assigned
  field :seat_assigned_by # User who assigned seat

  # Invitation
  field :invited_by       # User who invited this member
  field :invitation_accepted_at  # When invite was accepted

  # Status
  field :status           # active, suspended, pending_invite

  # Metadata
  field :created
  field :updated
  field :last_accessed    # Last time user accessed org resources

  # Audit
  field :disabled_at      # When membership was disabled
  field :disabled_by      # Who disabled it
end
```

**Redis Keys:**
- `membership:{membershipid}:object`
- `membership:org:{orgid}:user:{userid}` - Unique constraint lookup
- `user:{userid}:memberships` - Sorted set by created
- `organization:{orgid}:memberships` - Sorted set by created
- `organization:{orgid}:seats:consumed` - Count of active seats

**Key Principles:**
- One membership per user per organization
- Role determines organization-wide permissions
- Seat consumption is tracked explicitly
- Supports invitation workflow
- Can be suspended without deletion

---

### 1.4 Team (Sub-Organization Grouping)

**Purpose:** Groups of users within an organization for fine-grained access control and collaboration.

```ruby
class Team
  # Identity
  field :teamid           # Primary key (UUID)
  field :orgid            # Parent organization
  field :name             # Team name
  field :slug             # URL-friendly identifier (unique within org)
  field :description      # Team purpose/description

  # Hierarchy
  field :parent_team_id   # Parent team (for nested teams)

  # Settings
  field :settings         # JSON: team preferences

  # Metadata
  field :created
  field :updated
  field :created_by       # User who created team
  field :deleted_at       # Soft delete

  # Relationships
  has_many :team_memberships  # Users in this team
  has_many :secrets          # Team-scoped secrets
end
```

**Redis Keys:**
- `team:{teamid}:object`
- `team:org:{orgid}:slug:{slug}:teamid` - Unique within org
- `organization:{orgid}:teams` - Sorted set
- `team:{teamid}:memberships` - Sorted set of team membership IDs

**Key Principles:**
- Teams exist within organizations
- Support hierarchical nesting (optional)
- Slug unique within organization, not globally
- Teams do not consume seats (memberships do)

---

### 1.5 TeamMembership (User ↔ Team Junction)

**Purpose:** Assigns users to teams with team-specific roles.

```ruby
class TeamMembership
  # Identity
  field :team_membershipid  # Primary key
  field :teamid             # Team ID
  field :membershipid       # Organization Membership ID (not userid!)

  # Role
  field :team_role          # team_lead, team_member, team_viewer

  # Metadata
  field :created
  field :updated
  field :added_by           # Who added user to team
end
```

**Redis Keys:**
- `team_membership:{team_membershipid}:object`
- `team:{teamid}:memberships` - Sorted set
- `membership:{membershipid}:teams` - Sorted set of team IDs

**Key Principles:**
- References Membership, not User directly
- User must be org member before joining teams
- Team role is independent of org role
- Multiple teams per membership allowed

---

### 1.6 Subscription (Billing History)

**Purpose:** Historical record of all subscriptions for an organization.

```ruby
class Subscription
  # Identity
  field :subscriptionid       # Primary key
  field :orgid                # Organization
  field :stripe_subscription_id  # Stripe Subscription ID

  # Plan
  field :plan_id              # Plan identifier
  field :billing_cycle        # 'month' or 'year'
  field :quantity             # Number of seats purchased

  # Pricing
  field :amount               # Total amount (in cents)
  field :currency             # USD, EUR, etc.
  field :discount             # Discount details (JSON)

  # Period
  field :started_at           # Subscription start
  field :ended_at             # Subscription end (null if active)
  field :canceled_at          # When canceled (null if not canceled)
  field :trial_start          # Trial start date
  field :trial_end            # Trial end date

  # Status
  field :status               # active, trialing, past_due, canceled, expired

  # Metadata
  field :created
  field :updated
  field :created_by           # User who initiated subscription
  field :canceled_by          # User who canceled
  field :cancellation_reason  # Why it was canceled
end
```

**Redis Keys:**
- `subscription:{subscriptionid}:object`
- `organization:{orgid}:subscriptions` - Sorted set (historical)
- `organization:{orgid}:subscription:active` - String (current subscription ID)
- `subscription:stripe:{stripe_subscription_id}:id` - Lookup

**Key Principles:**
- Immutable historical record
- One active subscription per organization
- Tracks full lifecycle (trial → active → canceled → expired)
- Stripe is source of truth for billing

---

### 1.7 Plan (Entitlement Template)

**Purpose:** Defines capabilities and limits for each pricing tier.

```ruby
class Plan
  # Identity
  field :plan_id          # Primary key (anonymous, basic, identity, team, enterprise)
  field :name             # Display name
  field :description      # Plan description

  # Pricing (can be stored or fetched from Stripe)
  field :price_monthly    # Monthly price in cents
  field :price_yearly     # Yearly price in cents
  field :currency         # USD, EUR

  # Entitlements (capabilities)
  field :entitlements     # JSON hash of capabilities

  # Example entitlements structure:
  # {
  #   "api_enabled": true,
  #   "custom_domains": true,
  #   "max_secret_size_bytes": 10485760,  # 10MB
  #   "max_secret_ttl_seconds": 2592000,  # 30 days
  #   "email_delivery": true,
  #   "dark_mode": true,
  #   "max_secrets_per_month": null,      # null = unlimited
  #   "max_teams": 10,
  #   "priority_support": false,
  #   "sso_enabled": false,
  #   "audit_logs": false,
  #   "advanced_security": false
  # }

  # Seat Management
  field :minimum_seats    # Minimum seats required (1 for most, 5 for enterprise)
  field :maximum_seats    # Maximum seats allowed (null = unlimited)
  field :seat_cost        # Cost per additional seat (in cents)

  # Metadata
  field :active           # Is plan available for new signups?
  field :legacy           # Is this a legacy plan?
  field :created
  field :updated
end
```

**Redis Keys:**
- `plan:{plan_id}:object`
- `onetime:plan:values` - Sorted set of all plans

**Key Principles:**
- Plans define "what you can do" (entitlements)
- Roles define "who can do it" (permissions)
- Plans are mostly immutable (versioned if needed)
- Entitlements are checked programmatically, not hard-coded

---

### 1.8 CustomDomain (Branding)

**Purpose:** Custom branded domains owned by organizations.

```ruby
class CustomDomain
  # Identity
  field :domainid             # Primary key
  field :display_domain       # Full domain (secrets.example.com)
  field :orgid                # Owner organization (changed from custid)

  # Domain Components
  field :base_domain          # example.com
  field :subdomain            # secrets
  field :trd                  # Third-level domain
  field :sld                  # Second-level domain
  field :tld                  # Top-level domain

  # Verification
  field :verified             # Domain ownership verified
  field :resolving            # CNAME resolving status
  field :txt_validation_host  # TXT record host
  field :txt_validation_value # TXT record value
  field :status               # pending, verified, failed

  # Branding
  field :brand                # Brand settings (hashkey reference)
  field :logo                 # Logo image reference
  field :icon                 # Icon image reference

  # Metadata
  field :created
  field :updated
  field :created_by           # User who added domain
end
```

**Redis Keys:**
- `customdomain:{domainid}:object`
- `customdomain:display:{display_domain}:id` - Unique lookup
- `organization:{orgid}:domains` - Set of domain IDs

**Key Principles:**
- Owned by Organizations, not Users
- Requires plan entitlement (`custom_domains: true`)
- Verification required before activation
- Multiple domains per organization allowed

---

### 1.9 Session (Unchanged)

**Purpose:** User authentication sessions (remains largely the same).

```ruby
class Session
  field :sessid           # Primary key
  field :userid           # User ID (changed from custid)
  field :orgid            # Current organization context (NEW)
  field :ipaddress        # Client IP
  field :useragent        # Browser UA
  field :authenticated    # Auth status
  field :shrimp           # CSRF token
  field :referrer         # Referrer tracking
  field :created
  field :updated
  field :ttl              # 20 minutes default
end
```

**Key Changes:**
- References `userid` instead of `custid`
- Adds `orgid` to track current organization context
- Supports switching between organizations

---

### 1.10 Secret (Resource Ownership)

**Purpose:** Secrets now support both personal and organization ownership.

```ruby
class Secret
  # Existing fields...
  field :secretid
  field :metadataid
  field :passphrase
  field :secret_value
  field :ttl
  field :created

  # Ownership (mutually exclusive)
  field :userid           # Personal secret (user-owned)
  field :orgid            # Organization secret (org-owned)
  field :teamid           # Team secret (team-owned)

  # Creator tracking
  field :created_by       # User who created secret

  # Access tracking
  field :visibility       # 'personal', 'team', 'organization'
end
```

**Redis Keys:**
- `secret:{secretid}:object`
- `user:{userid}:secrets` - Personal secrets
- `organization:{orgid}:secrets` - Org secrets
- `team:{teamid}:secrets` - Team secrets

---

## 2. Entity Relationships

### 2.1 Entity-Relationship Diagram

```
┌──────────────┐
│     User     │
│  (Identity)  │
└──────┬───────┘
       │
       │ 1:N
       ▼
┌──────────────────┐           ┌─────────────────┐
│   Membership     │ N:1       │  Organization   │
│  (User ↔ Org)    │──────────▶│  (Billing Unit) │
└────────┬─────────┘           └────────┬────────┘
         │                              │
         │ N:M                          │ 1:N
         ▼                              ▼
┌──────────────────┐           ┌─────────────────┐
│ TeamMembership   │ N:1       │      Team       │
│  (User ↔ Team)   │──────────▶│   (Grouping)    │
└──────────────────┘           └─────────────────┘
                                        │
                                        │ 1:N
Organization 1:N                        ▼
         │                     ┌─────────────────┐
         ├────────────────────▶│     Secret      │
         │                     │   (Resource)    │
         │ 1:N                 └─────────────────┘
         ▼
┌─────────────────┐
│  Subscription   │
│   (Billing)     │
└────────┬────────┘
         │ N:1
         ▼
┌─────────────────┐
│      Plan       │
│ (Entitlements)  │
└─────────────────┘
```

### 2.2 Relationship Details

#### User → Membership → Organization
- **Cardinality:** User (1) → (N) Memberships (N) → (1) Organization
- **Constraint:** One membership per user per organization (unique index on userid+orgid)
- **Cascade Delete:** Deleting user soft-deletes all memberships
- **Business Rule:** User can be owner of multiple organizations

#### Organization → Subscription → Plan
- **Cardinality:** Organization (1) → (N) Subscriptions (historical), Organization (1) → (1) Active Subscription
- **Constraint:** Only one active subscription per organization
- **Cascade Delete:** Deleting organization preserves subscriptions (audit trail)
- **Business Rule:** Subscription change creates new record, ends old record

#### Organization → Team → TeamMembership → Membership
- **Cardinality:** Organization (1) → (N) Teams, Team (1) → (N) TeamMemberships, Membership (1) → (N) TeamMemberships
- **Constraint:** Team slug unique within organization
- **Cascade Delete:** Deleting team deletes team memberships
- **Business Rule:** User must be org member before joining team

#### Organization → CustomDomain
- **Cardinality:** Organization (1) → (N) CustomDomains
- **Constraint:** Display domain globally unique
- **Plan Requirement:** Requires `custom_domains` entitlement
- **Business Rule:** Unverified domains expire after 30 days

#### User/Organization/Team → Secret
- **Cardinality:** (1) → (N) Secrets (based on ownership type)
- **Constraint:** Secret has exactly one owner (userid OR orgid OR teamid, mutually exclusive)
- **Cascade Delete:** Deleting owner soft-deletes secrets (grace period)
- **Business Rule:** Visibility determines access rules

---

## 3. Role-Based Access Control (RBAC)

Inspired by **Kubernetes** and **OpenStack** multi-tenant RBAC patterns.

### 3.1 Role Hierarchy

#### Organization Roles

```
org_owner (highest privileges)
  ├─ Full billing control (view invoices, change plans, cancel subscription)
  ├─ Manage organization settings
  ├─ Add/remove members and assign roles
  ├─ Create/delete teams
  ├─ Transfer organization ownership
  └─ All org_admin capabilities

org_admin
  ├─ Manage members (invite, remove, change roles - except owner)
  ├─ Create/delete teams
  ├─ Manage organization settings (except billing)
  ├─ View all organization secrets
  └─ All org_member capabilities

org_billing
  ├─ View billing information
  ├─ Manage payment methods
  ├─ View/download invoices
  ├─ Change subscription plan
  └─ No access to secrets/teams

org_member (default role)
  ├─ Create/view/burn secrets within organization
  ├─ Join teams (if invited)
  ├─ View organization members
  └─ Access granted resources

org_viewer (read-only)
  ├─ View organization metadata
  ├─ View team structure
  ├─ View secrets they created
  └─ No modification rights
```

#### Team Roles

```
team_lead
  ├─ Add/remove team members
  ├─ Manage team settings
  ├─ View/burn all team secrets
  └─ All team_member capabilities

team_member (default)
  ├─ Create secrets scoped to team
  ├─ View team secrets (if team visibility allows)
  └─ Collaborate with team members

team_viewer
  ├─ View team metadata
  ├─ View team secrets they created
  └─ No modification rights
```

### 3.2 Permission Model

Following **OpenStack's RBAC model**, permissions are checked using:

```ruby
# Permission Check Pattern (pseudo-code)
def can?(user, action, resource, context = {})
  # Step 1: Resolve user's organization membership
  membership = Membership.find_by(userid: user.userid, orgid: context[:orgid])
  return false unless membership&.active?

  # Step 2: Check organization-level role
  if ORGANIZATION_ACTIONS[action].allowed_roles.include?(membership.role)
    return true
  end

  # Step 3: Check team-level role (if action is team-scoped)
  if context[:teamid]
    team_membership = TeamMembership.find_by(
      membershipid: membership.membershipid,
      teamid: context[:teamid]
    )
    return TEAM_ACTIONS[action].allowed_roles.include?(team_membership.team_role)
  end

  # Step 4: Check resource ownership
  if resource.respond_to?(:created_by) && resource.created_by == user.userid
    return true
  end

  false
end
```

### 3.3 Permission Matrix

| Action | org_owner | org_admin | org_billing | org_member | org_viewer |
|--------|-----------|-----------|-------------|------------|------------|
| **Billing** |||||
| View billing | ✓ | ✗ | ✓ | ✗ | ✗ |
| Change plan | ✓ | ✗ | ✓ | ✗ | ✗ |
| Cancel subscription | ✓ | ✗ | ✓ | ✗ | ✗ |
| **Members** |||||
| Invite members | ✓ | ✓ | ✗ | ✗ | ✗ |
| Remove members | ✓ | ✓ | ✗ | ✗ | ✗ |
| Change roles | ✓ | ✓* | ✗ | ✗ | ✗ |
| **Teams** |||||
| Create teams | ✓ | ✓ | ✗ | ✗ | ✗ |
| Delete teams | ✓ | ✓ | ✗ | ✗ | ✗ |
| Add team members | ✓ | ✓ | ✗ | team_lead | ✗ |
| **Secrets** |||||
| Create org secrets | ✓ | ✓ | ✗ | ✓ | ✗ |
| View all org secrets | ✓ | ✓ | ✗ | ✗ | ✗ |
| View own secrets | ✓ | ✓ | ✗ | ✓ | ✓ |
| Burn any secret | ✓ | ✓ | ✗ | ✗ | ✗ |
| **Organization** |||||
| Update settings | ✓ | ✓ | ✗ | ✗ | ✗ |
| Transfer ownership | ✓ | ✗ | ✗ | ✗ | ✗ |
| Delete organization | ✓ | ✗ | ✗ | ✗ | ✗ |

*org_admin cannot change owner role or promote to owner

---

## 4. Seat Management & Billing

Following **GitHub** and **Linear** best practices.

### 4.1 Seat Assignment Strategies

#### Strategy 1: Automatic Seat Assignment (Default)
- **Model:** All active members automatically consume seats
- **Billing:** `Organization.consumed_seats` = count of active memberships
- **Pros:** Simple, transparent, no manual management
- **Cons:** Can lead to unexpected charges
- **Use Case:** Small teams, trust-based organizations

#### Strategy 2: Manual Seat Assignment
- **Model:** Admins explicitly assign seats to members
- **Billing:** `Organization.consumed_seats` = count where `Membership.consumes_seat == true`
- **Pros:** Explicit cost control
- **Cons:** Requires admin overhead, potential seat contention
- **Use Case:** Large organizations, cost-sensitive environments

### 4.2 Seat Lifecycle

```
┌─────────────┐
│   Invited   │ (0 seats)
└──────┬──────┘
       │ accepts invite
       ▼
┌─────────────┐
│   Pending   │ (0 seats) - waiting for seat assignment
└──────┬──────┘
       │ seat assigned (manual) or auto-assigned
       ▼
┌─────────────┐
│   Active    │ (1 seat) - fully functional member
└──────┬──────┘
       │ suspended or seat revoked
       ▼
┌─────────────┐
│  Suspended  │ (0 seats) - membership exists, no access
└──────┬──────┘
       │ removed
       ▼
┌─────────────┐
│   Removed   │ (0 seats) - soft deleted
└─────────────┘
```

### 4.3 Billing Calculation

**Inspired by Linear's Stripe integration:**

```ruby
# Daily seat sync (runs at midnight UTC)
def sync_organization_seats(org)
  consumed = org.memberships.where(status: 'active', consumes_seat: true).count
  licensed = org.licensed_seats

  if consumed > licensed
    # Over-capacity: charge for additional seats (pro-rated)
    additional_seats = consumed - licensed
    Stripe::Subscription.update(
      org.stripe_subscription_id,
      items: [{
        id: org.stripe_subscription_item_id,
        quantity: consumed
      }]
    )
    org.update(licensed_seats: consumed)
  elsif consumed < licensed
    # Under-capacity: schedule downgrade for next billing cycle (no immediate refund)
    ScheduleSeatReduction.perform_at(org.current_period_end, org.orgid, consumed)
  end
end
```

**Proration Rules:**
- **Adding seats mid-cycle:** Pro-rated charge immediately
- **Removing seats mid-cycle:** Credit applied at next billing cycle (following GitHub model)
- **Annual subscriptions:** Pro-rated for remaining subscription year

### 4.4 Stripe Subscription Structure

```json
{
  "stripe_customer": {
    "id": "cus_...",
    "email": "billing@example.com",
    "metadata": {
      "orgid": "org_abc123",
      "plan_id": "team"
    }
  },
  "stripe_subscription": {
    "id": "sub_...",
    "customer": "cus_...",
    "items": [
      {
        "id": "si_...",
        "price": "price_team_monthly",
        "quantity": 5,
        "metadata": {
          "orgid": "org_abc123",
          "type": "seat"
        }
      }
    ],
    "metadata": {
      "orgid": "org_abc123",
      "plan_id": "team"
    }
  }
}
```

---

## 5. Migration Path from Current Model

### 5.1 Customer → User + Organization Migration

**Current State:**
- `Customer` model mixes identity and billing
- `custid` references email or 'anon'
- Subscriptions tied to customers

**Migration Strategy:**

#### Phase 1: Create parallel models (no breaking changes)
```ruby
# For each existing Customer record:
Customer.each do |cust|
  # Create User
  user = User.create!(
    userid: generate_uuid,
    email: cust.email,
    email_verified: cust.verified,
    passphrase: cust.passphrase,
    apitoken: cust.apitoken,
    display_name: cust.email.split('@').first,
    locale: cust.locale,
    created: cust.created,
    updated: cust.updated,
    contributor: cust.contributor,
    last_login: cust.last_login
  )

  # Create personal Organization (1:1 initially)
  org = Organization.create!(
    orgid: generate_uuid,
    name: "#{user.display_name}'s Organization",
    slug: generate_slug_from_email(user.email),
    owner_userid: user.userid,
    created_by: user.userid,

    # Migrate billing
    stripe_customer_id: cust.stripe_customer_id,
    stripe_subscription_id: cust.stripe_subscription_id,
    billing_email: cust.stripe_checkout_email || cust.email,
    plan_id: cust.planid,

    # Initial seat license
    licensed_seats: 1,
    consumed_seats: 1,

    created: cust.created,
    updated: cust.updated,
    verified: cust.verified
  )

  # Create Membership (user is owner)
  Membership.create!(
    membershipid: generate_uuid,
    orgid: org.orgid,
    userid: user.userid,
    role: 'org_owner',
    consumes_seat: true,
    status: 'active',
    seat_assigned_at: Time.now,
    created: cust.created
  )

  # Migrate custom domains
  CustomDomain.where(custid: cust.custid).update_all(orgid: org.orgid)

  # Migrate secrets
  Secret.where(custid: cust.custid).update_all(
    userid: nil,  # not personal
    orgid: org.orgid,
    created_by: user.userid,
    visibility: 'organization'
  )

  # Store mapping for rollback
  Migration::CustomerMapping.create!(
    custid: cust.custid,
    userid: user.userid,
    orgid: org.orgid
  )
end
```

#### Phase 2: Update sessions to reference userid
```ruby
Session.each do |sess|
  mapping = Migration::CustomerMapping.find_by(custid: sess.custid)
  if mapping
    sess.update!(
      userid: mapping.userid,
      orgid: mapping.orgid  # Set default org context
    )
  end
end
```

#### Phase 3: Deprecate Customer model
- Mark Customer model as deprecated
- Redirect all Customer reads to User model
- Log any remaining Customer writes
- Monitor for 30 days

#### Phase 4: Remove Customer model
- Delete Customer Redis keys
- Remove Customer class
- Clean up migration mapping

### 5.2 Redis Key Migration

**Before:**
```
customer:alice@example.com:object          # Old
session:sess_123:object                    # Old (custid reference)
customdomain:dom_abc:object                # Old (custid ownership)
```

**After:**
```
user:user_123:object                       # New
organization:org_456:object                # New
membership:mem_789:object                  # New
session:sess_123:object                    # Updated (userid+orgid reference)
customdomain:dom_abc:object                # Updated (orgid ownership)
```

**Migration Script:**
```ruby
# Rename and restructure keys atomically
def migrate_redis_keys
  redis = Familia.redis

  # Get all customer keys
  customer_keys = redis.keys('customer:*:object')

  customer_keys.each do |old_key|
    custid = old_key.match(/customer:(.*):object/)[1]
    mapping = Migration::CustomerMapping.find_by(custid: custid)
    next unless mapping

    # Get old data
    old_data = redis.hgetall(old_key)

    # Create new user key
    new_user_key = "user:#{mapping.userid}:object"
    redis.hmset(new_user_key, extract_user_fields(old_data))

    # Create new org key
    new_org_key = "organization:#{mapping.orgid}:object"
    redis.hmset(new_org_key, extract_org_fields(old_data))

    # Create membership key
    membership = Membership.find_by(userid: mapping.userid, orgid: mapping.orgid)
    new_mem_key = "membership:#{membership.membershipid}:object"
    redis.hmset(new_mem_key, membership.to_redis_hash)

    # Keep old key for rollback (TTL 30 days)
    redis.expire(old_key, 30.days.to_i)
  end
end
```

---

## 6. Plan Entitlements (Updated)

Expanding current 3-tier model to support organizations.

### 6.1 Proposed Plan Structure

#### Free Tier (Personal)
```ruby
{
  plan_id: 'free',
  name: 'Free',
  price_monthly: 0,
  price_yearly: 0,
  minimum_seats: 1,
  maximum_seats: 1,  # Personal only
  entitlements: {
    api_enabled: true,
    custom_domains: false,
    max_secret_size_bytes: 1048576,      # 1MB
    max_secret_ttl_seconds: 1209600,     # 14 days
    email_delivery: true,
    dark_mode: true,
    max_secrets_per_month: 100,
    max_teams: 0,                         # No teams
    priority_support: false,
    sso_enabled: false,
    audit_logs: false,
    advanced_security: false,
    organization_enabled: false           # Personal account only
  }
}
```

#### Pro Tier (Small Teams)
```ruby
{
  plan_id: 'pro',
  name: 'Pro',
  price_monthly: 1500,    # $15/seat/month
  price_yearly: 15000,    # $150/seat/year (2 months free)
  minimum_seats: 1,
  maximum_seats: 10,
  seat_cost: 1500,        # $15 per additional seat
  entitlements: {
    api_enabled: true,
    custom_domains: true,
    max_secret_size_bytes: 10485760,     # 10MB
    max_secret_ttl_seconds: 2592000,     # 30 days
    email_delivery: true,
    dark_mode: true,
    max_secrets_per_month: null,         # Unlimited
    max_teams: 5,
    priority_support: false,
    sso_enabled: false,
    audit_logs: false,
    advanced_security: false,
    organization_enabled: true
  }
}
```

#### Team Tier (Medium Organizations)
```ruby
{
  plan_id: 'team',
  name: 'Team',
  price_monthly: 2500,    # $25/seat/month
  price_yearly: 25000,    # $250/seat/year
  minimum_seats: 3,
  maximum_seats: 100,
  seat_cost: 2500,
  entitlements: {
    api_enabled: true,
    custom_domains: true,
    max_secret_size_bytes: 52428800,     # 50MB
    max_secret_ttl_seconds: 7776000,     # 90 days
    email_delivery: true,
    dark_mode: true,
    max_secrets_per_month: null,
    max_teams: 50,
    priority_support: true,
    sso_enabled: false,                   # Add-on available
    audit_logs: true,
    advanced_security: false,
    organization_enabled: true,
    role_based_access: true               # Full RBAC
  }
}
```

#### Enterprise Tier (Large Organizations)
```ruby
{
  plan_id: 'enterprise',
  name: 'Enterprise',
  price_monthly: null,    # Custom pricing
  price_yearly: null,
  minimum_seats: 10,
  maximum_seats: null,    # Unlimited
  seat_cost: null,        # Volume discounts
  entitlements: {
    api_enabled: true,
    custom_domains: true,
    max_secret_size_bytes: 104857600,    # 100MB
    max_secret_ttl_seconds: 31536000,    # 365 days
    email_delivery: true,
    dark_mode: true,
    max_secrets_per_month: null,
    max_teams: null,
    priority_support: true,
    sso_enabled: true,                    # SAML/OIDC
    audit_logs: true,
    advanced_security: true,              # IP whitelisting, 2FA enforcement
    organization_enabled: true,
    role_based_access: true,
    custom_contracts: true,
    dedicated_support: true,
    sla_guaranteed: true,
    on_premise_option: true               # Self-hosted option
  }
}
```

### 6.2 Entitlement Checking

```ruby
class Organization
  def entitled_to?(capability)
    plan = Plan.find(self.plan_id)
    return false unless plan

    entitlements = plan.entitlements

    # Boolean entitlements
    return entitlements[capability] if [true, false].include?(entitlements[capability])

    # Numeric/null entitlements (null = unlimited)
    entitlements[capability]
  end

  def can_create_secret?(size_bytes)
    max_size = entitled_to?(:max_secret_size_bytes)
    return false if max_size && size_bytes > max_size

    # Check monthly quota if applicable
    max_monthly = entitled_to?(:max_secrets_per_month)
    if max_monthly
      current_count = count_secrets_this_month
      return false if current_count >= max_monthly
    end

    true
  end

  def can_create_team?
    max_teams = entitled_to?(:max_teams)
    return false if max_teams == 0
    return true if max_teams.nil?  # Unlimited

    self.teams.count < max_teams
  end
end
```

---

## 7. Implementation Recommendations

### 7.1 Database Indexes (Redis Sorted Sets)

```ruby
# User indexes
onetime:user:values                        # All users (sorted by created)
user:email:{email}:userid                  # Email lookup (unique)

# Organization indexes
onetime:organization:values                # All orgs (sorted by created)
organization:slug:{slug}:orgid             # Slug lookup (unique)
organization:stripe:{stripe_customer_id}   # Stripe customer lookup

# Membership indexes
user:{userid}:memberships                  # User's orgs (sorted by created)
organization:{orgid}:memberships           # Org's members (sorted by created)
membership:org:{orgid}:user:{userid}       # Unique constraint

# Team indexes
organization:{orgid}:teams                 # Org's teams
team:{teamid}:memberships                  # Team members
membership:{membershipid}:teams            # Member's teams

# Subscription indexes
organization:{orgid}:subscriptions         # Historical subscriptions
organization:{orgid}:subscription:active   # Current subscription ID
subscription:stripe:{stripe_sub_id}        # Stripe subscription lookup
```

### 7.2 Validation Rules

```ruby
# User validations
- email format valid
- email unique globally
- email_verified before certain actions
- passphrase meets complexity requirements

# Organization validations
- name present (1-100 chars)
- slug unique globally, URL-safe
- owner_userid references valid user
- stripe_customer_id unique if present
- licensed_seats >= consumed_seats (warning if violated)

# Membership validations
- userid + orgid unique
- role in allowed list
- consumes_seat triggers seat check
- status in ['active', 'suspended', 'pending_invite']

# Team validations
- name present
- slug unique within organization
- parent_team_id references team in same org (prevent cycles)

# Subscription validations
- only one active subscription per org
- plan_id references valid plan
- quantity >= plan.minimum_seats
- quantity <= plan.maximum_seats (if not null)
```

### 7.3 Business Logic Guards

```ruby
# Before creating organization
- User must have verified email
- Check if user has reached org creation limit (spam prevention)

# Before adding member
- Check seat availability (if manual mode)
- Validate email domain (if allowed_email_domains set)
- Check plan's maximum_seats limit

# Before assigning seat
- Check licensed_seats >= consumed_seats + 1
- If over limit, trigger seat purchase flow

# Before upgrading plan
- Validate new plan supports current seat count
- Validate new plan supports current feature usage (teams, domains)

# Before downgrading plan
- Check if current usage exceeds new plan limits
- Prompt to remove excess teams/domains/etc.
```

### 7.4 API Design (Example Endpoints)

```
# Users
POST   /api/v3/users                      # Create user (signup)
GET    /api/v3/users/:userid              # Get user profile
PATCH  /api/v3/users/:userid              # Update user
DELETE /api/v3/users/:userid              # Delete user (soft delete)

# Organizations
POST   /api/v3/organizations              # Create organization
GET    /api/v3/organizations/:orgid       # Get organization
PATCH  /api/v3/organizations/:orgid       # Update organization
DELETE /api/v3/organizations/:orgid       # Delete organization

# Memberships
GET    /api/v3/organizations/:orgid/members              # List members
POST   /api/v3/organizations/:orgid/members              # Invite member
GET    /api/v3/organizations/:orgid/members/:membershipid
PATCH  /api/v3/organizations/:orgid/members/:membershipid  # Update role
DELETE /api/v3/organizations/:orgid/members/:membershipid  # Remove member

# Seat management
POST   /api/v3/organizations/:orgid/seats/assign         # Assign seat
POST   /api/v3/organizations/:orgid/seats/revoke         # Revoke seat
GET    /api/v3/organizations/:orgid/seats/usage          # Seat usage stats

# Teams
GET    /api/v3/organizations/:orgid/teams                # List teams
POST   /api/v3/organizations/:orgid/teams                # Create team
GET    /api/v3/organizations/:orgid/teams/:teamid
PATCH  /api/v3/organizations/:orgid/teams/:teamid
DELETE /api/v3/organizations/:orgid/teams/:teamid

# Team memberships
POST   /api/v3/teams/:teamid/members                     # Add member
DELETE /api/v3/teams/:teamid/members/:team_membershipid

# Subscriptions
GET    /api/v3/organizations/:orgid/subscription         # Current subscription
POST   /api/v3/organizations/:orgid/subscription         # Create subscription
PATCH  /api/v3/organizations/:orgid/subscription         # Update plan
DELETE /api/v3/organizations/:orgid/subscription         # Cancel

# Billing
GET    /api/v3/organizations/:orgid/billing              # Billing info
GET    /api/v3/organizations/:orgid/billing/invoices     # List invoices
POST   /api/v3/organizations/:orgid/billing/portal       # Stripe portal link
```

---

## 8. Testing Strategy

### 8.1 Unit Tests

```ruby
# User model tests
- User can be created with valid email
- User email must be unique
- User can have multiple memberships
- User deletion soft-deletes memberships

# Organization model tests
- Organization requires owner
- Organization slug is unique
- Organization can have multiple members
- Licensed seats cannot be less than consumed seats

# Membership model tests
- Membership enforces unique user+org
- Seat consumption increments consumed_seats counter
- Role validation restricts to allowed values
- Removing membership decrements consumed_seats

# Entitlement tests
- Plan entitlements are correctly checked
- Users are blocked when exceeding plan limits
- Plan upgrades grant new capabilities
- Plan downgrades enforce new limits
```

### 8.2 Integration Tests

```ruby
# Billing flow tests
- User creates organization and subscribes to paid plan
- Organization adds member, seat count increases, Stripe updated
- Organization removes member, seat count decreases, credit issued
- Subscription upgrade/downgrade flow works end-to-end

# RBAC tests
- org_owner can perform all actions
- org_admin cannot access billing
- org_member cannot invite users
- Team roles are enforced correctly

# Migration tests
- Customer migrates to User + Organization correctly
- All relationships preserved (domains, secrets, sessions)
- Redis keys migrated correctly
- Rollback restores original state
```

### 8.3 Performance Tests

```ruby
# Seat calculation performance
- Seat sync completes in <1s for org with 1000 members
- Concurrent seat assignments don't corrupt count

# Permission checks
- RBAC check completes in <10ms
- Membership lookup is O(1) via Redis hash

# Large organization tests
- Organization with 10,000 members performs well
- Team membership queries scale linearly
```

---

## 9. Security Considerations

### 9.1 Threats & Mitigations

| Threat | Mitigation |
|--------|-----------|
| **Unauthorized seat consumption** | Seat assignment requires org_admin role; audit log tracks assignments |
| **Billing manipulation** | Stripe is source of truth; webhooks validate all changes; subscription changes logged |
| **Privilege escalation** | org_admin cannot promote to owner; role changes logged; 2FA for owners |
| **Account takeover** | MFA enforcement per org; session timeout; suspicious login detection |
| **Data exfiltration** | Secrets scoped to org/team; RBAC enforced on read; audit logs for access |
| **Seat abuse (invite bombing)** | Rate limit on invitations; email verification required; seat cap enforcement |

### 9.2 Audit Logging

```ruby
class AuditLog
  field :audit_id         # Primary key
  field :orgid            # Organization context
  field :actor_userid     # Who performed action
  field :action           # 'member.invited', 'role.changed', 'subscription.upgraded', etc.
  field :target_type      # 'Membership', 'Subscription', etc.
  field :target_id        # ID of affected resource
  field :changes          # JSON: { from: old_value, to: new_value }
  field :ip_address       # Actor's IP
  field :user_agent       # Actor's browser
  field :created          # Timestamp
end
```

**Logged Events:**
- Membership changes (invite, remove, role change, seat assignment)
- Subscription changes (upgrade, downgrade, cancel, renew)
- Organization settings changes
- Team creation/deletion
- Custom domain verification
- Payment method updates

---

## 10. Open Questions & Future Considerations

### 10.1 Features to Defer (V2)

- **Hierarchical Organizations:** Parent/child org relationships (like AWS Organizations)
- **Cross-Organization Sharing:** Share secrets between orgs
- **Guest Access:** Limited access for external users (no seat consumption)
- **Service Accounts:** API-only accounts for automation
- **Usage-Based Billing:** Charge per secret created/burned (not just seats)
- **Advanced RBAC:** Custom roles with granular permissions
- **Single Sign-On (SSO):** SAML/OIDC for enterprise

### 10.2 Implementation Phases

**Phase 1: Foundation (This Document)**
- User, Organization, Membership, Team models
- Basic RBAC (org roles only)
- Seat-based billing
- Migration from Customer model
- ✅ Deliverable: Data model + migration plan

**Phase 2: Billing Integration**
- Stripe webhooks for seat sync
- Subscription lifecycle management
- Seat assignment workflows
- Billing portal integration

**Phase 3: Teams & Advanced RBAC**
- Team model implementation
- Team-based secret sharing
- Team roles and permissions
- Hierarchical team support (optional)

**Phase 4: Enterprise Features**
- SSO integration
- Advanced audit logging
- Custom SLAs
- Dedicated support channels

---

## 11. Summary

This data model provides a **clear separation of concerns**:

1. **User** = Individual identity (portable across organizations)
2. **Organization** = Billing entity (subscriptions, seats, domains)
3. **Membership** = User's relationship with organization (roles, seat consumption)
4. **Team** = Collaboration group within organization (fine-grained access)
5. **Subscription** = Billing history and entitlements
6. **Plan** = Capability definitions (what users can do)

**Key Benefits:**
- Eliminates "tier checks" on every page by checking entitlements at org level
- Supports multiple organizations per user (future growth)
- Clean migration path from existing Customer model
- Inspired by battle-tested SaaS patterns (GitHub, Notion, Linear)
- RBAC follows industry standards (Kubernetes, OpenStack)
- Stripe integration follows best practices

**Next Steps:**
1. Review and approve this data model
2. Create Ruby model implementations
3. Write migration scripts
4. Update API endpoints to support new models
5. Update UI to support organization context

---

## Appendix A: Comparison with Current Model

| Aspect | Current Model | Proposed Model |
|--------|--------------|----------------|
| **Identity** | Customer (custid = email) | User (userid = UUID) |
| **Billing Entity** | Customer | Organization |
| **Multi-User Support** | None | Yes (via Memberships) |
| **Role System** | 5 simple roles | 9 roles (5 org + 4 team) |
| **Seat Tracking** | Not applicable | Explicit per membership |
| **Team Collaboration** | None | Teams + TeamMemberships |
| **Custom Domains** | Per customer (1:N) | Per organization (1:N) |
| **Subscriptions** | One per customer | Multiple historical per org |
| **Secret Ownership** | Customer only | User, Org, or Team |
| **API Tokens** | Per customer | Per user (personal) + org tokens (future) |
| **Plan Entitlements** | Hard-coded checks | Dynamic entitlement system |

---

## Appendix B: Redis Memory Estimation

Assuming **10,000 organizations** with **average 5 members each**:

```
Users: 50,000 users × 2KB each = 100MB
Organizations: 10,000 orgs × 3KB each = 30MB
Memberships: 50,000 memberships × 1KB each = 50MB
Teams: 20,000 teams × 1KB each = 20MB
Team Memberships: 60,000 × 0.5KB = 30MB
Subscriptions: 50,000 historical × 1KB = 50MB (with 30-day TTL cleanup)
Plans: 5 plans × 2KB = 10KB (negligible)
Custom Domains: 5,000 domains × 1KB = 5MB

Total: ~285MB for core data
Indexes/Sets: ~50MB additional
Sessions (assuming 5000 active): ~10MB

Grand Total: ~350MB for 10K organizations
```

Redis can easily handle millions of organizations with this model.

---

**Document End**
