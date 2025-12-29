# lib/onetime/models/organization_membership.rb
#
# frozen_string_literal: true

require 'securerandom'

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
    feature :safe_dump

    prefix :org_membership
    identifier_field :objid

    # API serialization fields
    # Use safe_dump for consistent API responses across all invitation endpoints
    safe_dump_fields(
      { id: ->(obj) { obj.objid } },
      { organization_id: ->(obj) { obj.organization&.extid } },
      { email: ->(obj) { obj.invited_email } },
      :role,
      :status,
      :invited_by,
      :invited_at,
      { expires_at: ->(obj) { obj.invitation_expires_at } },
      { expired: ->(obj) { obj.expired? } },
      :resend_count,
      :token,
    )

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

    # Composite indexes for org-scoped lookups
    # Note: These use string keys combining the two fields
    unique_index :org_email_key, :org_email_lookup
    unique_index :org_customer_key, :org_customer_lookup

    def init
      @status       ||= 'active'
      @role         ||= 'member'
      @joined_at    ||= Familia.now.to_f if @status == 'active'
      @resend_count ||= 0
      nil
    end

    # Composite index key methods
    # These generate deterministic keys for org-scoped lookups

    # Key for finding pending invites by org + email
    # Only set for pending invitations (customer_objid is nil)
    def org_email_key
      return nil unless organization_objid && invited_email

      "#{organization_objid}:#{invited_email.to_s.downcase}"
    end

    # Key for finding active memberships by org + customer
    # Only set for active memberships (customer_objid is set)
    def org_customer_key
      return nil unless organization_objid && customer_objid

      "#{organization_objid}:#{customer_objid}"
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

    # Calculate invitation expiration timestamp (for API responses)
    # Returns nil for non-pending invitations
    def invitation_expires_at
      return nil unless invited_at

      invited_at.to_f + 7.days.to_i
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

    # Get the customer who sent this invitation
    # Memoized to avoid repeated Redis lookups within same request
    def inviter
      return nil unless invited_by

      @inviter ||= Onetime::Customer.load(invited_by)
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
    #
    # Updates the membership record to active status and adds the customer
    # to the organization's member sorted set.
    #
    # @param customer [Onetime::Customer] The customer accepting the invite
    # @return [Boolean] true if acceptance succeeded
    def accept!(customer)
      raise Onetime::Problem, 'Invitation already accepted' if active?
      raise Onetime::Problem, 'Invitation expired' if expired?
      raise Onetime::Problem, 'Invitation declined' if status == 'declined'
      raise Onetime::Problem, 'Email mismatch' if invited_email && customer.email != invited_email

      self.customer_objid = customer.objid
      self.status         = 'active'
      self.joined_at      = Familia.now.to_f
      self.token          = nil  # Clear token for security
      save

      # Update the org_customer_lookup index since customer_objid changed
      # This index enables find_by_org_customer to work for active memberships
      if org_customer_key
        self.class.org_customer_lookup[org_customer_key] = objid
      end

      # Add customer to organization's member sorted set directly
      # We bypass add_members_instance because that uses :through which would
      # try to create a new OrganizationMembership (we already have one - this invitation)
      org   = organization
      score = Familia.now.to_f
      if org
        org.members.add(customer.objid, score)
        org.pending_invitations.remove(objid) # Remove from pending set
      end
      true
    end

    # Decline a pending invitation
    def decline!
      raise Onetime::Problem, 'Cannot decline active membership' if active?

      self.status = 'declined'
      self.token  = nil
      save

      # Remove from org's pending set
      organization&.pending_invitations&.remove(objid)
    end

    # Revoke a pending invitation (by org owner/admin)
    def revoke!
      raise Onetime::Problem, 'Can only revoke pending invitations' unless pending?

      # Remove from org's pending set before destroying
      organization&.pending_invitations&.remove(objid)

      # Use destroy_with_index_cleanup! to prevent orphaned Redis index entries
      destroy_with_index_cleanup!
    end

    # Destroy the membership with proper index cleanup
    #
    # Cleans up all unique index entries before destroying the record,
    # which allows the email to be re-invited later.
    def destroy_with_index_cleanup!
      # Remove org_email_lookup entry if exists
      # Use remove_field since the index is a Familia::HashKey
      if org_email_key
        self.class.org_email_lookup.remove_field(org_email_key)
      end

      # Remove org_customer_lookup entry if exists
      if org_customer_key
        self.class.org_customer_lookup.remove_field(org_customer_key)
      end

      # Remove token_lookup entry if exists
      if token
        self.class.token_lookup.remove_field(token)
      end

      destroy!
    end

    # Generate a secure invitation token
    # 256-bit entropy (32 bytes) for security
    def generate_token!
      self.token = SecureRandom.urlsafe_base64(32)
    end

    class << self
      # Create a new invitation for an organization
      #
      # @param organization [Organization] the organization inviting
      # @param email [String] the email address to invite
      # @param role [String] the role to assign ('member', 'admin')
      # @param inviter [Customer] the customer creating the invite
      # @return [OrganizationMembership] the created invitation
      # @raise [Onetime::Problem] if invitation already exists for this email
      def create_invitation!(organization:, email:, inviter:, role: 'member')
        email = email.to_s.strip.downcase

        # Check for existing pending invitation
        existing = find_by_org_email(organization.objid, email)
        raise Onetime::Problem, 'Invitation already pending for this email' if existing&.pending?

        # Generate token before create! so it's included in index population
        token = SecureRandom.urlsafe_base64(32)

        # Use create! for proper Familia index auto-population
        membership = create!(
          organization_objid: organization.objid,
          invited_email: email,
          role: role,
          status: 'pending',
          invited_by: inviter.objid,
          invited_at: Familia.now.to_f,
          joined_at: nil,
          resend_count: 0,
          token: token,
        )

        # Add to org's pending_invitations set for efficient querying
        organization.pending_invitations.add(membership.objid)

        membership
      end

      # Find an invitation by its secure token
      #
      # @param token [String] the invitation token
      # @return [OrganizationMembership, nil] the invitation or nil if not found
      def find_by_token(token)
        return nil if token.nil? || token.empty?

        objid = token_lookup[token]
        return nil unless objid

        load(objid)
      end

      # Find an invitation by organization and email
      #
      # @param org_objid [String] the organization's objid
      # @param email [String] the invited email address
      # @return [OrganizationMembership, nil] the invitation or nil if not found
      def find_by_org_email(org_objid, email)
        return nil if org_objid.nil? || email.nil?

        key   = "#{org_objid}:#{email.to_s.strip.downcase}"
        objid = org_email_lookup[key]
        return nil unless objid

        load(objid)
      end

      # Find a membership by organization and customer
      #
      # @param org_objid [String] the organization's objid
      # @param customer_objid [String] the customer's objid
      # @return [OrganizationMembership, nil] the membership or nil if not found
      def find_by_org_customer(org_objid, customer_objid)
        return nil if org_objid.nil? || customer_objid.nil?

        key   = "#{org_objid}:#{customer_objid}"
        objid = org_customer_lookup[key]
        return nil unless objid

        load(objid)
      end

      # Find pending invitations for an organization
      #
      # Uses the organization's pending_invitations sorted set for O(n) lookup
      # where n is only the number of pending invitations for this org,
      # not all OrganizationMembership instances globally.
      #
      # @param org [Organization] the organization to query
      # @return [Array<OrganizationMembership>] pending invitations
      def pending_for_org(org)
        org.list_pending_invitations.select(&:pending?)
      end

      # Find active memberships for an organization
      #
      # Uses batch lookup via HMGET on the org_customer_lookup index,
      # then bulk loads all memberships with load_multi.
      #
      # @param org [Organization] the organization to query
      # @return [Array<OrganizationMembership>] active memberships
      def active_for_org(org)
        customer_objids = org.members.to_a
        return [] if customer_objids.empty?

        # Build composite keys for batch lookup: "org_objid:customer_objid"
        composite_keys = customer_objids.map { |cust_objid| "#{org.objid}:#{cust_objid}" }

        # Batch lookup via HMGET (single Redis call instead of N)
        membership_objids = org_customer_lookup.values_at(*composite_keys).compact

        # Bulk load all memberships (single MGET instead of N HGETALL)
        load_multi(membership_objids).compact.select(&:active?)
      end
    end
  end
end
