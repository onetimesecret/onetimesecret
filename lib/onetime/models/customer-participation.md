# Participation Relationships Example

## Basic Declaration

```ruby
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :customer_id
  field :customer_id, :name, :tier, :joined_at

  # Define participation relationships
  participates_in Team, :members, score: :joined_at
  participates_in Organization, :members
  participates_in Organization, :vip_members, score: -> { tier == 'premium' ? 100 : 0 }

  def init
    @customer_id ||= "cust_#{SecureRandom.hex(4)}"
  end
end

class Team < Familia::Horreum
  feature :relationships

  identifier_field :team_id
  field :team_id, :name, :department

  def init
    @team_id ||= "team_#{SecureRandom.hex(4)}"
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
customer.teams                  # → [Team, Team, ...] All teams customer belongs to
customer.team_ids               # → ["team_123", "team_456"] Just the IDs (efficient)
customer.teams?                 # → true/false Has any team memberships?
customer.teams_count            # → 3 Count without loading objects

customer.organizations          # → [Organization, ...] All orgs customer belongs to
customer.organization_ids       # → ["org_123", "org_456"] Just the IDs
customer.organizations?         # → true/false Has any org memberships?
customer.organizations_count    # → 2 Count of organization memberships

# EXISTING PARTICIPANT METHODS (per-instance operations)
customer.in_team_members?(team)              # → true/false
customer.add_to_team_members(team)           # → Add self to specific team
customer.remove_from_team_members(team)      # → Remove from specific team
customer.score_in_team_members(team)         # → Get score in specific team

customer.in_organization_members?(org)       # → true/false
customer.add_to_organization_members(org)    # → Add self to specific org
customer.remove_from_organization_members(org) # → Remove from specific org

# Participation tracking (unchanged)
customer.participations                      # → UnsortedSet of collection keys
customer.current_participations              # → Detailed participation metadata
```

### On Team & Organization (Target Classes)

```ruby
# EXISTING TARGET METHODS (unchanged)
team.members                    # → Familia::SortedSet
team.add_member(customer)       # → Add with calculated score
team.remove_member(customer)    # → Remove and clean reverse index
team.add_members([c1, c2, c3])  # → Bulk addition

organization.members             # → Familia::SortedSet
organization.vip_members         # → Familia::SortedSet
organization.add_member(customer)
organization.add_vip_member(customer)
```

## Usage Examples

### Creating Relationships

```ruby
# Create instances
customer = Customer.create(name: "Alice Corp", tier: "premium")
team1 = Team.create(name: "Engineering", department: "Tech")
team2 = Team.create(name: "Support", department: "Service")
org = Organization.create(name: "TechCo", type: "employer")

# Establish relationships (unchanged - still works both ways)
team1.add_member(customer)           # From target side
customer.add_to_team_members(team2)  # From participant side
org.add_member(customer)
org.add_vip_member(customer)         # Premium tier gets score 100
```

### Querying Relationships - The Game Changer

**Before (Complex Manual Parsing):**
```ruby
# OLD WAY - What we had to do before
team_keys = customer.participations.members.select { |k|
  k.start_with?("team:") && k.end_with?(":members")
}
team_ids = team_keys.map { |k| k.split(':')[1] }.uniq
teams = Team.multiget(*team_ids).compact
```

**After (Simple Direct Access):**
```ruby
# NEW WAY - Clean and intuitive
customer.teams                      # → [team1, team2]
customer.teams.map(&:name)          # → ["Engineering", "Support"]
customer.teams?                     # → true
customer.teams_count                # → 2

# Multiple relationship types
customer.organizations              # → [org]
customer.organizations.first.name   # → "TechCo"

# Efficient ID-only access (no object loading)
customer.team_ids                   # → ["team_abc123", "team_def456"]
customer.organization_ids           # → ["org_xyz789"]
```

### Custom Reverse Method Names

```ruby
class Employee < Familia::Horreum
  feature :relationships

  # Default pluralization
  participates_in Team, :members              # → employee.teams

  # Custom reverse method name
  participates_in Team, :contractors, reverse: :contracting_teams
  # → employee.contracting_teams (instead of employee.teams)

  participates_in Organization, :staff, reverse: :employers
  # → employee.employers (instead of employee.organizations)
end

# Usage
employee.contracting_teams          # → Teams where employee is contractor
employee.employers                  # → Organizations employing this person
employee.teams                      # → Teams where employee is member
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
if customer.teams?
  puts "Customer belongs to #{customer.teams_count} teams"
end

# ID-only operations for foreign key scenarios
team_ids = customer.team_ids
TeamMailer.notify_all(team_ids)  # Pass IDs without loading objects

# Bulk operations still supported
customers = Customer.multiget(*team.members.to_a)  # Forward direction
teams = Team.multiget(*customer.team_ids)          # Reverse direction

# Lazy loading pattern
class Customer < Familia::Horreum
  def active_teams
    @active_teams ||= teams.select(&:active?)
  end
end
```

## Complete Symmetry Example

```ruby
# Both directions are now equally convenient:

# Forward: Team → Customers (unchanged)
team.members                        # → SortedSet of customer IDs
team.members.size                   # → Count
customers = Customer.multiget(*team.members.to_a)

# Reverse: Customer → Teams (NEW!)
customer.teams                      # → Array of Team objects
customer.teams_count                # → Count
customer.team_ids                   # → Array of team IDs

# True bidirectional operations
team.add_member(customer)           # Updates both sides
# Equivalent to:
customer.add_to_team_members(team)  # Also updates both sides

team.remove_member(customer)        # Cleans both sides
# Equivalent to:
customer.remove_from_team_members(team)  # Also cleans both sides
```

## Key Benefits Summary

1. **Symmetric API**: Both directions are equally easy to query
2. **Intuitive naming**: `customer.teams` reads naturally
3. **Performance options**: Choose between full objects, IDs only, or just counts
4. **Custom naming**: Override when pluralization doesn't fit
5. **Backwards compatible**: All existing methods continue to work
6. **Zero configuration**: Just works with `participates_in` declaration

This completes the vision of truly bidirectional relationships in Familia - making it as easy to go from participant to targets as it is to go from targets to participants.
