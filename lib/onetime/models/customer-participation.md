## Participation Relationships Example

```ruby
class Customer < Familia::Horreum
  feature :relationships
  participates_in :Organization, :members, score: :joined
  participates_in :Team, :members
  # ...
end
```

### What class and instance methods are created for each of the 3 models involved in these participation relationships?

*Referenced documentation:*
- `docs/guides/feature-relationships.md` (205 lines)
- `docs/guides/feature-relationships-methods.md` (755 lines)

Looking at your participation relationships, here are all the methods that would be generated for the three models involved:

#### 1. Customer (Participant) Instance Methods

**For Organization relationship:**

```ruby
# Membership operations
customer.in_organization_members?(organization)        # Check membership
customer.add_to_organization_members(organization)     # Add self with :joined score
customer.add_to_organization_members(organization, 100) # Add self with explicit score
customer.remove_from_organization_members(organization) # Remove self

# Score operations (sorted_set)
customer.score_in_organization_members(organization)   # Get current score
```

**For Team relationship:**

```ruby
# Membership operations
customer.in_team_members?(team)              # Check membership
customer.add_to_team_members(team)           # Add self (default score)
customer.add_to_team_members(team, 50)       # Add self with explicit score
customer.remove_from_team_members(team)      # Remove self

# Score operations (sorted_set by default)
customer.score_in_team_members(team)         # Get current score
```

**Participation tracking (shared):**

```ruby
customer.participations                      # Access reverse index UnsortedSet
customer.current_participations              # Detailed participation metadata
```

#### 2. Organization Instance Methods

```ruby
# Collection access
organization.members                         # Returns Familia::SortedSet
organization.members?                        # Boolean type verification
organization.members=                        # Replace DataType instance

# Single item operations
organization.add_member(customer)            # Add with customer's :joined score
organization.add_member(customer, 100)       # Add with explicit score
organization.remove_member(customer)         # Remove from collection

# Bulk operations
organization.add_members([cust1, cust2])     # Efficient bulk addition

# Permission queries (if ScoreEncoding available)
organization.members_with_permission(:read)  # Filtered by encoded score
```

#### 3. Team Instance Methods

```ruby
# Collection access
team.members                                 # Returns Familia::SortedSet
team.members?                                # Boolean type verification
team.members=                                # Replace DataType instance

# Single item operations
team.add_member(customer)                    # Add with calculated score
team.add_member(customer, 75)                # Add with explicit score
team.remove_member(customer)                 # Remove from collection

# Bulk operations
team.add_members([cust1, cust2, cust3])      # Efficient bulk addition

# Permission queries (if ScoreEncoding available)
team.members_with_permission(:write)         # Filtered by encoded score
```

#### Auto-Generated Infrastructure

**On Customer:**

```ruby
# Automatically created if not already defined
set :participations  # Reverse index for tracking all relationships
```

**On Organization & Team:**

```ruby
# Automatically created by participates_in
sorted_set :members  # Collection field (since score is used/default)
```

#### Key Points

1. **Collection Type**: Both use sorted_set (Organization explicitly via score, Team by default)
2. **Method Naming**: Follows pattern `{action}_{target_snake_case}_{collection_name}`
3. **Bidirectional**: Updates to either side automatically maintain reverse index
4. **Score Handling**:
   - Organization uses `:joined` field from Customer
   - Team uses default scoring (likely `Familia.now.to_f`)
5. **Transactional**: All add/remove operations wrapped in transactions for atomicity

The relationships are fully bidirectional and automatically synchronized - calling `organization.add_member(customer)` is equivalent to calling `customer.add_to_organization_members(organization)`.

### How to get the list of teams a customer is participating in

From a customer instance, there are several ways to get the teams they're participating in:

#### 1. Using current_participations (Recommended)

```ruby
# Get detailed participation metadata
participations = customer.current_participations

# Filter for Team participations
team_participations = participations.select { |p| p[:target_class] == "Team" }

# Extract team IDs
team_ids = team_participations.map { |p| p[:target_id] }

# Load the Team objects
teams = Team.multiget(*team_ids).compact
```

#### 2. Using the participations reverse index directly

```ruby
# Get raw participation keys (e.g., "team:team_123:members")
participation_keys = customer.participations.members

# Parse Team keys and extract IDs
team_keys = participation_keys.select { |key| key.start_with?("team:") }
team_ids = team_keys.map { |key| key.split(':')[1] }  # Extract the ID portion

# Load Team objects
teams = Team.multiget(*team_ids).compact
```

#### 3. Helper method approach (add to your Customer class)

```ruby
class Customer < Familia::Horreum
  feature :relationships

  def teams
    @teams ||= begin
      # Use current_participations for cleaner extraction
      team_participations = current_participations.select { |p|
        p[:target_class] == "Team" && p[:collection_name] == :members
      }
      team_ids = team_participations.map { |p| p[:target_id] }
      Team.multiget(*team_ids).compact
    end
  end

  def organizations
    @organizations ||= begin
      org_participations = current_participations.select { |p|
        p[:target_class] == "Organization" && p[:collection_name] == :members
      }
      org_ids = org_participations.map { |p| p[:target_id] }
      Organization.multiget(*org_ids).compact
    end
  end
end
```

#### 4. With score information

If you need the scores (e.g., when they joined), `current_participations` provides that:

```ruby
customer.current_participations.select { |p| p[:target_class] == "Team" }
# Returns array of hashes like:
# [
#   {
#     target_class: "Team",
#     target_id: "team_123",
#     collection_name: :members,
#     type: :sorted_set,
#     score: 1704067200.0,
#     decoded_score: { ... }  # If score encoding is used
#   }
# ]
```

#### Example Usage

```ruby
# Get all teams for a customer
customer = Customer.find(customer_id)
teams = customer.teams  # Using helper method

# Or inline
team_ids = customer.current_participations
  .select { |p| p[:target_class] == "Team" }
  .map { |p| p[:target_id] }
teams = Team.multiget(*team_ids).compact

# Iterate through teams
teams.each do |team|
  puts "Customer is member of: #{team.name}"
end
```

The `current_participations` method is the most robust approach as it provides complete metadata about all relationships, including the score (when joined), collection type, and any permission encoding if used.
