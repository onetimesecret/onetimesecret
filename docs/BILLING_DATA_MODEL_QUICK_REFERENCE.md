# Billing Data Model - Quick Reference

**Last Updated:** 2025-11-09

This is a quick reference companion to `BILLING_DATA_MODEL.md`. Use this for fast lookups of entity structures and relationships.

---

## Entity Hierarchy at a Glance

```
User (Identity)
  └─ owns → Organizations (1:N)
  └─ belongs to → Organizations via Memberships (N:M)
      └─ has role → org_owner, org_admin, org_billing, org_member, org_viewer
      └─ consumes seat → boolean
      └─ belongs to → Teams (via TeamMemberships)
          └─ has team role → team_lead, team_member, team_viewer

Organization (Billing Unit)
  ├─ has → Subscription (1:1 active, 1:N historical)
  │   └─ uses → Plan (defines entitlements)
  ├─ owns → CustomDomains (1:N)
  ├─ contains → Teams (1:N)
  └─ owns → Secrets (1:N)
```

---

## Core Entities - Field Summary

### User
```yaml
userid:           UUID (PK)
email:            unique
email_verified:   boolean
passphrase:       encrypted
apitoken:         string
display_name:     string
locale:           string
created/updated:  timestamps
```

### Organization
```yaml
orgid:                  UUID (PK)
name/slug:              unique identifier
owner_userid:           User.userid
stripe_customer_id:     Stripe Customer
stripe_subscription_id: Stripe Subscription (active)
plan_id:                Plan.plan_id
licensed_seats:         integer (paid seats)
consumed_seats:         integer (active members with seats)
billing_cycle:          'month' | 'year'
created/updated:        timestamps
```

### Membership
```yaml
membershipid:     UUID (PK)
orgid:            Organization.orgid
userid:           User.userid
role:             org_owner | org_admin | org_billing | org_member | org_viewer
consumes_seat:    boolean
status:           active | suspended | pending_invite
created/updated:  timestamps

# Unique constraint: (orgid, userid)
```

### Team
```yaml
teamid:           UUID (PK)
orgid:            Organization.orgid
name/slug:        unique within org
parent_team_id:   Team.teamid (optional, for hierarchy)
created/updated:  timestamps

# Unique constraint: (orgid, slug)
```

### TeamMembership
```yaml
team_membershipid:  UUID (PK)
teamid:             Team.teamid
membershipid:       Membership.membershipid (NOT userid!)
team_role:          team_lead | team_member | team_viewer
created/updated:    timestamps
```

### Subscription
```yaml
subscriptionid:         UUID (PK)
orgid:                  Organization.orgid
stripe_subscription_id: Stripe Subscription
plan_id:                Plan.plan_id
quantity:               integer (seats)
amount:                 integer (cents)
billing_cycle:          'month' | 'year'
status:                 active | trialing | past_due | canceled | expired
started_at/ended_at:    timestamps
```

### Plan
```yaml
plan_id:          free | pro | team | enterprise (PK)
name:             display name
price_monthly:    integer (cents)
price_yearly:     integer (cents)
minimum_seats:    integer
maximum_seats:    integer or null (unlimited)
seat_cost:        integer (cents per seat)
entitlements:     JSON (capabilities)
```

---

## Role Permissions - Quick Matrix

| Action | org_owner | org_admin | org_billing | org_member | org_viewer |
|--------|:---------:|:---------:|:-----------:|:----------:|:----------:|
| Manage billing | ✓ | ✗ | ✓ | ✗ | ✗ |
| Invite/remove members | ✓ | ✓ | ✗ | ✗ | ✗ |
| Change member roles | ✓ | ✓* | ✗ | ✗ | ✗ |
| Create/delete teams | ✓ | ✓ | ✗ | ✗ | ✗ |
| Create secrets | ✓ | ✓ | ✗ | ✓ | ✗ |
| View all org secrets | ✓ | ✓ | ✗ | ✗ | ✗ |
| View own secrets | ✓ | ✓ | ✗ | ✓ | ✓ |
| Update org settings | ✓ | ✓ | ✗ | ✗ | ✗ |
| Transfer ownership | ✓ | ✗ | ✗ | ✗ | ✗ |
| Delete organization | ✓ | ✗ | ✗ | ✗ | ✗ |

*org_admin cannot change owner role or promote others to owner

---

## Team Permissions

| Action | team_lead | team_member | team_viewer |
|--------|:---------:|:-----------:|:-----------:|
| Add/remove team members | ✓ | ✗ | ✗ |
| Manage team settings | ✓ | ✗ | ✗ |
| Create team secrets | ✓ | ✓ | ✗ |
| View team secrets | ✓ | ✓ | ✓ (own only) |
| Burn team secrets | ✓ | ✓ (own only) | ✗ |

---

## Plan Comparison

| Feature | Free | Pro | Team | Enterprise |
|---------|:----:|:---:|:----:|:----------:|
| **Price/seat/month** | $0 | $15 | $25 | Custom |
| **Min seats** | 1 | 1 | 3 | 10 |
| **Max seats** | 1 | 10 | 100 | Unlimited |
| **Organizations** | ✗ | ✓ | ✓ | ✓ |
| **Teams** | 0 | 5 | 50 | Unlimited |
| **Custom domains** | ✗ | ✓ | ✓ | ✓ |
| **Max secret size** | 1MB | 10MB | 50MB | 100MB |
| **Max secret TTL** | 14 days | 30 days | 90 days | 365 days |
| **API access** | ✓ | ✓ | ✓ | ✓ |
| **Email delivery** | ✓ | ✓ | ✓ | ✓ |
| **Priority support** | ✗ | ✗ | ✓ | ✓ |
| **SSO (SAML/OIDC)** | ✗ | ✗ | ✗ | ✓ |
| **Audit logs** | ✗ | ✗ | ✓ | ✓ |
| **Advanced security** | ✗ | ✗ | ✗ | ✓ |

---

## Seat Management Cheat Sheet

### Seat Lifecycle States

```
Invited → Pending → Active (seat consumed) → Suspended → Removed
   ↓          ↓         ↓                        ↓           ↓
0 seats   0 seats   1 seat                   0 seats    0 seats
```

### When Seats Are Consumed

| Action | Seats Changed? | Billing Impact |
|--------|----------------|----------------|
| Invite member | ✗ (not yet) | None |
| Member accepts invite (auto mode) | ✓ +1 | Pro-rated charge |
| Admin assigns seat (manual mode) | ✓ +1 | Pro-rated charge |
| Suspend member | ✓ -1 | Credit at next cycle |
| Remove member | ✓ -1 | Credit at next cycle |
| Change to org_viewer | ✗ (policy dependent) | Configurable |

### Billing Proration Rules

| Event | Charge Timing | Calculation |
|-------|---------------|-------------|
| Add seat mid-month | Immediate | `(seat_cost × days_remaining) / days_in_cycle` |
| Remove seat mid-month | Next billing cycle | No immediate refund, credit applied |
| Annual subscription + seat | Immediate | `(seat_cost × months_remaining) / 12` |
| Upgrade plan | Immediate | Pro-rated difference for current cycle |
| Downgrade plan | Next billing cycle | No immediate refund |

---

## Redis Key Patterns - Quick Lookup

### Users
```
user:{userid}:object                    # User data
user:email:{email}:userid               # Email → userid
user:{userid}:memberships               # Sorted set of membership IDs
```

### Organizations
```
organization:{orgid}:object             # Org data
organization:slug:{slug}:orgid          # Slug → orgid
organization:{orgid}:memberships        # Sorted set
organization:{orgid}:teams              # Sorted set
organization:{orgid}:subscription:active # Current subscription ID
```

### Memberships
```
membership:{membershipid}:object        # Membership data
membership:org:{orgid}:user:{userid}    # Unique constraint lookup
organization:{orgid}:seats:consumed     # Counter (cached)
```

### Teams
```
team:{teamid}:object                    # Team data
team:org:{orgid}:slug:{slug}:teamid     # Unique within org
team:{teamid}:memberships               # Sorted set of team_membership IDs
```

### Subscriptions
```
subscription:{subscriptionid}:object    # Subscription data
subscription:stripe:{stripe_id}:id      # Stripe → internal ID
organization:{orgid}:subscriptions      # Sorted set (historical)
```

---

## Migration Mapping (Customer → User/Org)

### Current Model
```ruby
Customer {
  custid: "alice@example.com"  # Email or 'anon'
  email: "alice@example.com"
  planid: "identity"
  stripe_customer_id: "cus_..."
  stripe_subscription_id: "sub_..."
}
```

### New Model
```ruby
User {
  userid: "user_abc123"
  email: "alice@example.com"
  # Personal identity fields
}

Organization {
  orgid: "org_xyz789"
  name: "Alice's Organization"
  owner_userid: "user_abc123"
  plan_id: "identity"
  stripe_customer_id: "cus_..."      # Migrated
  stripe_subscription_id: "sub_..."  # Migrated
  licensed_seats: 1
  consumed_seats: 1
}

Membership {
  membershipid: "mem_def456"
  userid: "user_abc123"
  orgid: "org_xyz789"
  role: "org_owner"
  consumes_seat: true
}
```

### Migration Script Pattern
```ruby
Customer.each do |cust|
  user = create_user_from_customer(cust)
  org = create_personal_org_for_user(user, cust)
  membership = create_owner_membership(user, org)
  migrate_custom_domains(cust, org)
  migrate_secrets(cust, user, org)
end
```

---

## Common Queries - Pseudo-SQL

### Get all organizations for a user
```ruby
user.memberships.map(&:organization)
# Redis: SMEMBERS user:{userid}:memberships → get each membership → get org
```

### Get all members of an organization
```ruby
organization.memberships.includes(:user)
# Redis: SMEMBERS organization:{orgid}:memberships → get each membership + user
```

### Check if user has role in org
```ruby
membership = Membership.find_by(userid: user.userid, orgid: org.orgid)
membership.role == 'org_admin'
# Redis: GET membership:org:{orgid}:user:{userid} → HGET membership:{id}:object role
```

### Get current subscription for org
```ruby
org.subscription_id  # Cached on org object
# Or: GET organization:{orgid}:subscription:active → GET subscription:{id}:object
```

### Check plan entitlement
```ruby
plan = Plan.find(org.plan_id)
plan.entitlements['custom_domains']
# Redis: HGET plan:{plan_id}:object entitlements → JSON parse → key lookup
```

### Count consumed seats
```ruby
Membership.where(orgid: org.orgid, status: 'active', consumes_seat: true).count
# Redis: GET organization:{orgid}:seats:consumed (cached counter)
# Or: SMEMBERS organization:{orgid}:memberships → filter by status + consumes_seat
```

---

## API Endpoint Examples

### Organization Management
```bash
# Create organization
POST /api/v3/organizations
{
  "name": "Acme Inc",
  "slug": "acme",
  "billing_email": "billing@acme.com"
}

# Get organization
GET /api/v3/organizations/:orgid

# Update organization
PATCH /api/v3/organizations/:orgid
{
  "name": "Acme Corporation",
  "require_mfa": true
}

# Delete organization
DELETE /api/v3/organizations/:orgid
```

### Member Management
```bash
# List members
GET /api/v3/organizations/:orgid/members

# Invite member
POST /api/v3/organizations/:orgid/members
{
  "email": "newmember@example.com",
  "role": "org_member",
  "auto_assign_seat": true
}

# Update member role
PATCH /api/v3/organizations/:orgid/members/:membershipid
{
  "role": "org_admin"
}

# Remove member
DELETE /api/v3/organizations/:orgid/members/:membershipid
```

### Team Management
```bash
# Create team
POST /api/v3/organizations/:orgid/teams
{
  "name": "Engineering",
  "slug": "engineering"
}

# Add user to team
POST /api/v3/teams/:teamid/members
{
  "membershipid": "mem_abc123",
  "team_role": "team_member"
}
```

### Subscription Management
```bash
# Get current subscription
GET /api/v3/organizations/:orgid/subscription

# Upgrade plan
PATCH /api/v3/organizations/:orgid/subscription
{
  "plan_id": "team",
  "quantity": 10
}

# Cancel subscription
DELETE /api/v3/organizations/:orgid/subscription
{
  "cancellation_reason": "No longer needed"
}

# Get billing portal link (Stripe)
POST /api/v3/organizations/:orgid/billing/portal
# Returns: { "url": "https://billing.stripe.com/..." }
```

---

## Validation Rules Summary

### User
- Email format valid + unique globally
- Password complexity: min 8 chars, mix of upper/lower/number
- Email must be verified before creating organizations

### Organization
- Name: 1-100 characters
- Slug: 3-50 characters, alphanumeric + hyphens, globally unique
- Owner must be verified user
- Licensed seats ≥ consumed seats (enforced on seat assignment)

### Membership
- (userid, orgid) pair unique
- Role must be in allowed list
- Cannot assign seat if org at capacity (unless triggering purchase flow)

### Team
- Name: 1-100 characters
- Slug: unique within organization (not globally)
- Parent team must be in same organization
- Cannot create circular hierarchy

### Subscription
- Only one active subscription per org
- Quantity ≥ plan.minimum_seats
- Quantity ≤ plan.maximum_seats (if not null)
- Plan must be active (not legacy/deprecated)

---

## Security Checklist

- [ ] All role changes logged in audit log
- [ ] Seat assignments trigger billing updates
- [ ] Organization owners require MFA (optional per-org setting)
- [ ] API rate limiting per user + per org
- [ ] CSRF tokens on all state-changing operations
- [ ] Stripe webhook signature verification
- [ ] Email verification before org creation
- [ ] Invitation links expire after 7 days
- [ ] Soft delete preserves audit trail (30-90 day retention)
- [ ] Payment method changes send notification emails

---

## Performance Benchmarks (Target)

| Operation | Target Latency | Notes |
|-----------|----------------|-------|
| User lookup by email | <5ms | Redis hash lookup |
| Org membership check | <10ms | Cached on session |
| RBAC permission check | <10ms | In-memory role matrix |
| Seat count calculation | <50ms | Cached counter, updated on change |
| List org members (100 members) | <100ms | Paginated results |
| Create membership + seat assignment | <200ms | Includes Stripe API call |
| Stripe webhook processing | <500ms | Background job for heavy work |

---

## Common Gotchas

1. **Membership references User, TeamMembership references Membership**
   - Don't reference `userid` in TeamMembership; use `membershipid`

2. **Seats are org-level, not team-level**
   - Teams don't consume additional seats
   - One user in 10 teams = still 1 seat

3. **Plan changes don't auto-migrate data**
   - Downgrading from 10 teams to 5 requires manual team removal
   - Check current usage before allowing downgrade

4. **Stripe is source of truth for billing**
   - Don't modify subscription status locally
   - Always sync from Stripe webhooks

5. **Email uniqueness is global, slugs are per-org**
   - User email: globally unique
   - Org slug: globally unique
   - Team slug: unique within org only

6. **Soft deletes preserve audit trail**
   - Don't hard delete users/orgs
   - Set `deleted_at` timestamp
   - Clean up after grace period (30-90 days)

7. **Sessions track org context**
   - User can belong to multiple orgs
   - Session stores current `orgid`
   - Switch orgs = update session, don't re-authenticate

---

## Next Steps After Approval

1. **Phase 1: Model Implementation**
   - Create Ruby model classes
   - Implement Redis Familia mappings
   - Write model validations

2. **Phase 2: Migration Scripts**
   - Customer → User + Organization migration
   - CustomDomain ownership update (custid → orgid)
   - Secret ownership migration
   - Session reference updates

3. **Phase 3: API Updates**
   - Create v3 API endpoints
   - Deprecate v2 endpoints referencing Customer
   - Update authentication middleware (org context)

4. **Phase 4: Billing Integration**
   - Stripe webhook handlers for seat sync
   - Seat assignment workflows
   - Billing portal integration

5. **Phase 5: UI Updates**
   - Organization switcher
   - Member management interface
   - Team management interface
   - Billing/subscription UI

---

**For full details, see:** `BILLING_DATA_MODEL.md`
