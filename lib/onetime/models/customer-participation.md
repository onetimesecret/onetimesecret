# Participation Relationships Example

## Basic Declaration

```ruby
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :customer_id
  field :customer_id, :name, :tier, :joined_at

  # Define participation relationships
  participates_in Organization, :members, score: :joined_at
  participates_in Organization, :vip_members, score: -> { tier == 'premium' ? 100 : 0 }

  def init
    @customer_id ||= "cust_#{SecureRandom.hex(4)}"
  end
end

class Organization < Familia::Horreum
  feature :relationships

  identifier_field :org_id
  field :org_id, :name, :type

  def init
    @org_id ||= "org_#{SecureRandom.hex(4)}"
  end
end
```

## Generated Methods Reference

### On Customer (Participant) - NEW Reverse Collection Methods

```ruby
# AUTO-GENERATED REVERSE COLLECTIONS (NEW!)
customer.organizations          # → [Organization, ...] All orgs customer belongs to
customer.organization_ids       # → ["org_123", "org_456"] Just the IDs
customer.organizations?         # → true/false Has any org memberships?
customer.organizations_count    # → 2 Count of organization memberships

# EXISTING PARTICIPANT METHODS (per-instance operations)
customer.in_organization_members?(org)       # → true/false
customer.add_to_organization_members(org)    # → Add self to specific org
customer.remove_from_organization_members(org) # → Remove from specific org
customer.score_in_organization_members(org)  # → Get score in specific org

# Participation tracking (unchanged)
customer.participations                      # → UnsortedSet of collection keys
customer.current_participations              # → Detailed participation metadata
```

### On Organization (Target Class)

```ruby
# EXISTING TARGET METHODS (unchanged)
organization.members             # → Familia::SortedSet
organization.add_member(customer)
organization.remove_member(customer)    # → Remove and clean reverse index
organization.add_members([c1, c2, c3])  # → Bulk addition
```

## Usage Examples

### Creating Relationships

```ruby
# Create instances
customer = Customer.create(name: "Alice Corp", tier: "premium")
org1 = Organization.create(name: "TechCo", type: "employer")
org2 = Organization.create(name: "StartupHub", type: "partner")

# Establish relationships (unchanged - still works both ways)
org1.add_member(customer)                    # From target side
customer.add_to_organization_members(org2)   # From participant side
org1.add_vip_member(customer)                # Premium tier gets score 100
```

### Querying Relationships - The Game Changer

**Before (Complex Manual Parsing):**
```ruby
# OLD WAY - What we had to do before
org_keys = customer.participations.members.select { |k|
  k.start_with?("organization:") && k.end_with?(":members")
}
org_ids = org_keys.map { |k| k.split(':')[1] }.uniq
orgs = Organization.multiget(*org_ids).compact
```

**After (Simple Direct Access):**
```ruby
# NEW WAY - Clean and intuitive
customer.organizations              # → [org1, org2]
customer.organizations.map(&:name)  # → ["TechCo", "StartupHub"]
customer.organizations?             # → true
customer.organizations_count        # → 2

# Efficient ID-only access (no object loading)
customer.organization_ids           # → ["org_xyz789", "org_abc123"]
```

### Custom Reverse Method Names

```ruby
class Employee < Familia::Horreum
  feature :relationships

  # Default pluralization
  participates_in Organization, :members      # → employee.organizations

  # Custom reverse method name
  participates_in Organization, :staff, reverse: :employers
  # → employee.employers (instead of employee.organizations)

  participates_in Organization, :contractors, reverse: :contracting_orgs
  # → employee.contracting_orgs (instead of employee.organizations)
end

# Usage
employee.employers                  # → Organizations employing this person
employee.contracting_orgs           # → Organizations where employee is contractor
employee.organizations              # → Organizations where employee is member
```

### Multiple Collections in Same Target

```ruby
class User < Familia::Horreum
  feature :relationships

  # Can participate in multiple collections of same target class
  participates_in Project, :contributors      # → user.projects (all)
  participates_in Project, :maintainers       # → user.projects (all)
  participates_in Project, :reviewers         # → user.projects (all)
end

# The reverse method shows ALL projects (union of all collections)
user.projects  # → All projects where user is contributor, maintainer, OR reviewer

# For specific collections, use the per-instance methods
user.in_project_contributors?(project)  # → Check specific role
user.in_project_maintainers?(project)
user.in_project_reviewers?(project)
```

## Performance Patterns

```ruby
# Efficient membership checking (no object loading)
if customer.organizations?
  puts "Customer belongs to #{customer.organizations_count} organizations"
end

# ID-only operations for foreign key scenarios
org_ids = customer.organization_ids
OrgMailer.notify_all(org_ids)  # Pass IDs without loading objects

# Bulk operations still supported
customers = Customer.multiget(*organization.members.to_a)  # Forward direction
orgs = Organization.multiget(*customer.organization_ids)   # Reverse direction

# Lazy loading pattern
class Customer < Familia::Horreum
  def active_organizations
    @active_organizations ||= organizations.select(&:active?)
  end
end
```

## Complete Symmetry Example

```ruby
# Both directions are now equally convenient:

# Forward: Organization → Customers (unchanged)
organization.members                # → SortedSet of customer IDs
organization.members.size           # → Count
customers = Customer.multiget(*organization.members.to_a)

# Reverse: Customer → Organizations (NEW!)
customer.organizations              # → Array of Organization objects
customer.organizations_count        # → Count
customer.organization_ids           # → Array of org IDs

# True bidirectional operations
organization.add_member(customer)           # Updates both sides
# Equivalent to:
customer.add_to_organization_members(organization)  # Also updates both sides

organization.remove_member(customer)        # Cleans both sides
# Equivalent to:
customer.remove_from_organization_members(organization)  # Also cleans both sides
```

## Key Benefits Summary

1. **Symmetric API**: Both directions are equally easy to query
2. **Intuitive naming**: `customer.organizations` reads naturally
3. **Performance options**: Choose between full objects, IDs only, or just counts
4. **Custom naming**: Override when pluralization doesn't fit
5. **Backwards compatible**: All existing methods continue to work
6. **Zero configuration**: Just works with `participates_in` declaration

This completes the vision of truly bidirectional relationships in Familia - making it as easy to go from participant to targets as it is to go from targets to participants.
