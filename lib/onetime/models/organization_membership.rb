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
  # Opaque Identifier Pattern:
  # API responses return organization.extid (not objid) to prevent enumeration.
  # See safe_dump_fields for serialization details.
  #
  class OrganizationMembership < Familia::Horreum
    using Familia::Refinements::TimeLiterals

    INVITATION_TTL_SECONDS = 7.days.to_i

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
      :domain_scope_id,
      { domain_scoped: ->(obj) { obj.domain_scoped? } },
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

    field :domain_scope_id

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

      "#{organization_objid}:#{OT::Utils.normalize_email(invited_email)}"
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
    def expired?(ttl_seconds = INVITATION_TTL_SECONDS)
      return false unless pending?
      return false unless invited_at

      (Familia.now.to_f - invited_at.to_f) > ttl_seconds
    end

    # Calculate invitation expiration timestamp (for API responses)
    # Returns nil for non-pending invitations
    def invitation_expires_at
      return nil unless invited_at

      invited_at.to_f + INVITATION_TTL_SECONDS
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

    def org_scoped?
      domain_scope_id.to_s.empty?
    end

    def domain_scoped?
      !org_scoped?
    end

    # Fail-closed: nil domain = no access (either a bug upstream
    # or a legitimate "no domain context" case — deny either way).
    def can_access_domain?(domain)
      return false if domain.nil?

      org_scoped? || domain_scope_id == domain.objid
    end

    # Accept a pending invitation
    #
    # Uses Familia's staged relationship activation to atomically:
    # - Add customer to org.members (active sorted set)
    # - Add org to customer's participation reverse index
    # - Remove from org.pending_invitations (staging set)
    # - Create composite-keyed through model
    # - Destroy UUID-keyed staged model
    #
    # OTS-specific index transitions are handled before/after activation:
    # - token_lookup: removed (pending-only index, token cleared for security)
    # - org_email_lookup: removed (pending-only index)
    # - org_customer_lookup: populated (active-only index)
    #
    # @param customer [Onetime::Customer] The customer accepting the invite
    # @return [Boolean] true if acceptance succeeded
    # @raise [Onetime::Problem] if invitation is expired or declined
    def accept!(customer)
      # Idempotency guard: if the customer was concurrently added to the org
      # (e.g. by another process calling add_members_instance), return the
      # existing membership rather than attempting a second activation that
      # could corrupt indexes or fail on the already-destroyed staged model.
      if active? || organization&.member?(customer)
        OT.info "[accept!] Customer #{customer.custid} already active in org #{organization_objid} — skipping activation"
        return true
      end

      raise Onetime::Problem, 'Invitation expired' if expired?
      raise Onetime::Problem, 'Invitation declined' if status == 'declined'

      emails_match = invited_email.nil? ||
                     OT::Utils.normalize_email(customer.email) ==
                     OT::Utils.normalize_email(invited_email)
      raise Onetime::Problem, 'Email mismatch' unless emails_match

      # Capture values from staged model before activation destroys it
      old_token              = token
      old_org_email_key      = org_email_key
      carry_role             = role
      carry_invited_email    = invited_email
      carry_invited_by       = invited_by
      carry_invited_at       = invited_at
      carry_resend_count     = resend_count
      carry_domain_scope_id  = domain_scope_id

      org = organization
      raise Onetime::Problem, 'Organization not found' unless org

      # Clean up pending-state OTS indexes BEFORE activation.
      # The staged model's save populated these indexes. The activated model
      # will re-populate org_email_lookup (same key, new objid) during its save,
      # so we must remove the old entry first to avoid RecordExistsError.
      self.class.token_lookup.remove_field(old_token) if old_token
      self.class.org_email_lookup.remove_field(old_org_email_key) if old_org_email_key

      begin
        # Activate via Familia staged relationships: handles the three-structure
        # invariant (active set + reverse index + staging set removal) atomically,
        # then creates composite-keyed through model and destroys this UUID model.
        activated = org.activate_members_instance(
          self,
          customer,
          through_attrs: {
            role: carry_role,
            status: 'active',
            invited_email: carry_invited_email,
            invited_by: carry_invited_by,
            invited_at: carry_invited_at,
            joined_at: Familia.now.to_f,
            resend_count: carry_resend_count,
            domain_scope_id: carry_domain_scope_id,
            token: nil, # Clear token for security
          },
        )
      rescue Familia::Problem, Redis::BaseError, Onetime::Problem
        # Restore pending-state indexes so the invitation remains discoverable
        # if activation fails (e.g. Redis/network error, validation error).
        self.class.token_lookup[old_token]             = objid if old_token
        self.class.org_email_lookup[old_org_email_key] = objid if old_org_email_key
        raise
      end

      # Populate active-state OTS index on the NEW composite-keyed model
      if activated.org_customer_key
        self.class.org_customer_lookup[activated.org_customer_key] = activated.objid
      end

      # Update in-memory state so callers see the accepted state.
      # The UUID-keyed Redis entry is already destroyed by activate.
      # Setting objid to the composite key ensures that refresh! and
      # load(objid) work correctly post-accept.
      self.objid          = activated.objid
      self.customer_objid = customer.objid
      self.status         = 'active'
      self.joined_at      = activated.joined_at
      self.token          = nil

      true
    end

    # Decline a pending invitation
    #
    # Cleans up indexes to prevent stale entries from accumulating:
    #   - token_lookup: removed (token is cleared anyway)
    #   - org_email_lookup: removed (allows re-invitation to same email)
    #   - pending_invitations: removed from staging set (quota accuracy)
    #
    # The record itself is preserved with status='declined' for audit purposes.
    # Does NOT use unstage_members_instance because that destroys the model.
    #
    def decline!
      raise Onetime::Problem, 'Cannot decline active membership' if active?

      # Capture old token before clearing (needed for index cleanup)
      old_token = token

      self.status = 'declined'
      self.token  = nil
      save

      # Clean up indexes AFTER save (save re-adds indexes via auto_update_class_indexes)
      self.class.token_lookup.remove_field(old_token) if old_token
      self.class.org_email_lookup.remove_field(org_email_key) if org_email_key

      # Remove from org's pending_invitations staging set (preserves the record)
      organization&.pending_invitations&.remove(objid)
    end

    # Revoke a pending invitation (by org owner/admin)
    #
    # Uses Familia's unstage to remove from staging set and destroy the model,
    # plus OTS-specific index cleanup for token_lookup and org_email_lookup.
    def revoke!
      raise Onetime::Problem, 'Can only revoke pending invitations' unless pending?

      org = organization

      # Clean up OTS-specific indexes before unstaging destroys the model
      self.class.token_lookup.remove_field(token) if token
      self.class.org_email_lookup.remove_field(org_email_key) if org_email_key
      self.class.org_customer_lookup.remove_field(org_customer_key) if org_customer_key

      if org
        # Use Familia staged relationship: removes from pending_invitations set
        # and destroys the UUID-keyed through model
        org.unstage_members_instance(self)
      else
        # Organization was deleted — destroy the orphaned model directly
        destroy!
      end
    end

    # Destroy the membership with proper index cleanup
    #
    # DESIGN NOTE: This method exists because Familia's base destroy! only
    # deletes the object's Redis hash. It intentionally doesn't know about
    # application-level indexes (pending_invitations, unique lookups) because:
    #
    #   1. Familia is ORM-layer; indexes are application-layer concerns
    #   2. Different operations need different cleanup (accept vs decline vs revoke)
    #   3. Follows ORM patterns where relationship cleanup is opt-in
    #
    # Always use semantic methods (revoke!, decline!, accept!) for business
    # operations. Use this method for safe deletion in tests/migrations.
    # Only use raw destroy! when you explicitly want no cleanup.
    #
    # Cleans up:
    #   - org.members sorted set (ZREM customer from org's active members)
    #   - customer.participations reverse index (SREM org collection key)
    #   - org_email_lookup (allows email to be re-invited)
    #   - org_customer_lookup
    #   - token_lookup
    #   - pending_invitations staging set (prevents stale quota counts)
    #
    def destroy_with_index_cleanup!
      org  = organization
      cust = customer

      # Remove from Familia sorted sets (the same work remove_members_instance does).
      # Guard on both org and cust existing — pending invitations have no customer.
      if org && cust
        # ZREM customer from org's members sorted set.
        # Pass the Customer object, not a string — the sorted set was created
        # without reference: true, so a raw string would be JSON-encoded and
        # not match the identifier stored when the object was added.
        org.members.remove(cust)

        # SREM org's members collection key from customer's participations reverse index
        cust.untrack_participation_in(org.members.dbkey) if cust.respond_to?(:untrack_participation_in)
      end

      # Remove OTS application-level indexes

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

      # Remove from org's pending_invitations staging set if still pending
      # This prevents stale objids from affecting quota calculations
      organization&.pending_invitations&.remove(objid) if pending?

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
      # Uses Familia's staged relationships to create a UUID-keyed through model
      # in the pending_invitations staging set. The model is NOT in the active
      # members set until accept! is called (which triggers activate_members_instance).
      #
      # @param organization [Organization] the organization inviting
      # @param email [String] the email address to invite
      # @param role [String] the role to assign ('member', 'admin')
      # @param inviter [Customer] the customer creating the invite
      # @return [OrganizationMembership] the created invitation (UUID-keyed staged model)
      # @raise [Onetime::Problem] if invitation already exists for this email
      def create_invitation!(organization:, email:, inviter:, role: 'member')
        email = OT::Utils.normalize_email(email)

        # Check for existing pending invitation
        existing = find_by_org_email(organization.objid, email)
        raise Onetime::Problem, 'Invitation already pending for this email' if existing&.pending?

        # Generate token before staging so it's included in index population
        token = SecureRandom.urlsafe_base64(32)

        # Use Familia staged relationship: creates UUID-keyed through model
        # and adds its objid to the org's pending_invitations staging sorted set.
        # The stage method sets organization_objid automatically via target FK.
        organization.stage_members_instance(
          through_attrs: {
            invited_email: email,
            role: role,
            status: 'pending',
            invited_by: inviter.objid,
            invited_at: Familia.now.to_f,
            joined_at: nil,
            resend_count: 0,
            token: token,
          },
        )
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

        key   = "#{org_objid}:#{OT::Utils.normalize_email(email)}"
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

      # Find all memberships scoped to a specific custom domain.
      #
      # Used for cascade cleanup when a domain is deleted — all memberships
      # whose access was granted by that domain's IdP should be removed.
      #
      # Scans the organization's active members and filters by domain_scope_id.
      # This is O(n) over the org's member count, which is acceptable because:
      # - Domain deletion is rare (admin action)
      # - Per-org member counts are small (tens to low hundreds)
      # - Avoids maintaining an additional global index
      #
      # @param domain_objid [String] the custom domain's objid
      # @param organization [Organization, nil] optional — if not provided,
      #   loads the domain to find its primary organization
      # @return [Array<OrganizationMembership>] memberships scoped to this domain
      def find_all_by_domain_scope(domain_objid, organization: nil)
        return [] if domain_objid.nil? || domain_objid.to_s.empty?

        org = organization
        unless org
          domain = Onetime::CustomDomain.find_by_identifier(domain_objid)
          org    = domain&.primary_organization
        end
        return [] unless org

        active_for_org(org).select { |m| m.domain_scope_id == domain_objid }
      end

      # Ensure a customer has an active membership in an organization.
      #
      # Convergence point for all "add a known customer" paths (SSO, CLI,
      # join request approval). Checks for a pending invitation first --
      # if one exists, activates it (staged -> active). Otherwise creates
      # a new membership directly.
      #
      # Familia provides four primitives: stage, activate, unstage, add.
      # This method composes activate + add with a domain-specific lookup
      # (find_by_org_email) that Familia can't perform -- matching a staged
      # model's invited_email against the participant's email is OTS
      # domain knowledge.
      #
      # Race safety: Between the member? check (ZSCORE) and mutation
      # (accept! or add_members_instance), another process may complete
      # the same work. Both code paths handle this:
      # - accept! may raise if the staged model was already activated;
      #   we rescue and return the now-existing membership.
      # - add_members_instance is idempotent (Familia find_or_create).
      # - revoke! may raise if another process activated the invitation
      #   between our check and revoke; we rescue and fall through.
      #
      # @param organization [Organization]
      # @param customer [Customer]
      # @param role [String] 'member' or 'admin' (only used for direct add;
      #   when activating a pending invitation, the invitation's role is used)
      # @param domain_scope_id [String, nil] Set once at first join. Re-login
      #   returns existing membership unchanged — scope is immutable short of
      #   explicit admin upgrade to org-scope.
      # @return [OrganizationMembership] the active membership (composite-keyed)
      def ensure_membership(organization, customer, role: 'member', domain_scope_id: nil)
        return find_by_org_customer(organization.objid, customer.objid) if organization.member?(customer)

        pending = find_by_org_email(organization.objid, customer.email)

        if pending&.pending? && !pending.expired?
          begin
            pending.accept!(customer)
          rescue Onetime::Problem, Familia::Problem, ArgumentError
            # Another process already activated this invitation or the staged
            # model was destroyed mid-flight. The customer may now be a member
            # — fall through to the final lookup below.
            nil
          end
        else
          # Clean up expired/declined pending invitation before direct add
          # to prevent stale entries from counting against quotas.
          if pending&.pending?
            begin
              pending.revoke!
            rescue Onetime::Problem
              # Another process activated the invitation between our check
              # and the revoke attempt. No cleanup needed — the invitation
              # is no longer pending.
              nil
            end
          end

          organization.add_members_instance(
            customer,
            through_attrs: {
              role: role,
              status: 'active',
              joined_at: Familia.now.to_f,
              domain_scope_id: domain_scope_id,
            },
          )
        end

        # Final convergence lookup: regardless of which path succeeded
        # (this process or a concurrent one), the membership now exists.
        find_by_org_customer(organization.objid, customer.objid)
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
