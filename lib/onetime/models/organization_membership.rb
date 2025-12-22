# lib/onetime/models/organization_membership.rb
#
# frozen_string_literal: true

module Onetime
  # OrganizationMembership - Through model for Organization/Customer participation
  #
  # This model is auto-created/destroyed by Familia's participates_in :through option.
  # It stores rich membership data (roles, invitations, audit trails) beyond what
  # the sorted set membership tracking provides.
  #
  # Key Structure:
  #   Redis key: organization:{org.objid}:customer:{cust.objid}:org_membership
  #   The key is deterministic, enabling direct lookup without scanning.
  #
  # Usage:
  #   # Auto-created when adding member with :through
  #   membership = org.add_members_instance(customer, through_attrs: { role: 'admin' })
  #   membership.role  #=> 'admin'
  #
  #   # Chaining pattern
  #   membership = org.add_members_instance(customer)
  #   membership.role = 'owner'
  #   membership.save
  #
  #   # Auto-destroyed when removing member
  #   org.remove_members_instance(customer)  # Destroys membership too
  #
  # Invitation Flow (pending status):
  #   # Create invite for non-existent user
  #   membership = OrganizationMembership.new(
  #     organization_objid: org.objid,
  #     invited_email: 'user@example.com',
  #     status: 'pending',
  #     token: SecureRandom.urlsafe_base64(32)
  #   )
  #   membership.save
  #
  #   # Accept invite (customer_objid nil -> filled, status -> active)
  #
  class OrganizationMembership < Familia::Horreum
    using Familia::Refinements::TimeLiterals

    # REQUIRED: Through models must have object_identifier for deterministic keys
    feature :object_identifier
    feature :relationships

    prefix :org_membership
    identifier_field :objid

    # Foreign keys - auto-set by ThroughModelOperations
    # Pattern: {prefix}_objid matches Familia's auto-set convention
    field :organization_objid  # FK to Organization (always set)
    field :customer_objid      # FK to Customer (nil for pending invites)

    # Role hierarchy: owner > admin > member
    # - owner: Full access, billing, delete org
    # - admin: Manage members, settings (no billing/delete)
    # - member: Use features, view members
    field :role

    # Status: active, pending, declined, expired
    field :status

    # Invitation tracking
    field :invited_by       # Customer objid who sent invite
    field :invited_email    # Email for pending invites (before account exists)
    field :invited_at       # Timestamp of invitation
    field :resend_count     # Number of times invite was resent

    # Membership timestamps
    field :joined_at        # When membership became active

    # Cache invalidation - auto-set by ThroughModelOperations
    field :updated_at

    # Secure token for invitation links
    # Format: /invite/:token
    field :token

    # Indexes for fast lookups
    unique_index :token, :token_lookup

    def init
      @status ||= 'active'
      @role ||= 'member'
      @joined_at ||= Familia.now.to_f if @status == 'active'
      @resend_count ||= 0
      nil
    end

    # Check if this is an active membership
    def active?
      status == 'active'
    end

    # Check if this is a pending invitation
    def pending?
      status == 'pending'
    end

    # Check if invitation has expired (7 days by default)
    def expired?(ttl_seconds = 7.days.to_i)
      return false unless pending?
      return false unless invited_at

      (Familia.now.to_f - invited_at.to_f) > ttl_seconds
    end

    # Get the organization this membership belongs to
    # Memoized to avoid repeated Redis lookups within same request
    def organization
      return nil unless organization_objid

      @organization ||= Onetime::Organization.load(organization_objid)
    end

    # Get the customer (member) this membership belongs to
    # Memoized to avoid repeated Redis lookups within same request
    def customer
      return nil unless customer_objid

      @customer ||= Onetime::Customer.load(customer_objid)
    end

    # Role checks
    def owner?
      role == 'owner'
    end

    def admin?
      role == 'admin' || owner?
    end

    def member?
      role == 'member' || admin?
    end

    # Accept a pending invitation
    # @param customer [Onetime::Customer] The customer accepting the invite
    # @return [Boolean] true if acceptance succeeded
    def accept!(customer)
      raise Onetime::Problem, 'Invitation already accepted' if active?
      raise Onetime::Problem, 'Invitation expired' if expired?
      raise Onetime::Problem, 'Invitation declined' if status == 'declined'
      raise Onetime::Problem, 'Email mismatch' if invited_email && customer.email != invited_email

      self.customer_objid = customer.objid
      self.status = 'active'
      self.joined_at = Familia.now.to_f
      self.token = nil  # Clear token for security
      save
    end

    # Decline a pending invitation
    def decline!
      raise Onetime::Problem, 'Cannot decline active membership' if active?

      self.status = 'declined'
      self.token = nil
      save
    end

    class << self
      # Find pending invitations for an organization
      def pending_for_org(org)
        # TODO: Implement with index when available
        # For now, this is a placeholder
        []
      end

      # Find active memberships for an organization
      #
      # Uses pipelined loading to fetch all memberships in a single Redis
      # round-trip, avoiding N+1 queries.
      #
      # @param org [Organization] the organization to query
      # @return [Array<OrganizationMembership>] active memberships
      def active_for_org(org)
        customers = org.list_members
        return [] if customers.empty?

        # Generate all keys upfront, then batch load via pipeline
        keys = customers.map { |customer| membership_key(org, customer) }
        load_multi_by_keys(keys).compact
      end

      private

      # Generate the deterministic Redis key for a membership
      #
      # @param org [Organization] the organization
      # @param customer [Customer] the customer
      # @return [String] the Redis key
      def membership_key(org, customer)
        "organization:#{org.objid}:customer:#{customer.objid}:org_membership"
      end
    end
  end
end
