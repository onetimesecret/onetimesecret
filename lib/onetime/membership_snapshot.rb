# lib/onetime/membership_snapshot.rb
#
# frozen_string_literal: true

module Onetime
  # One customer's organization memberships, read at most once per request.
  #
  # OrganizationLoader resolves the active organization during auth, the
  # bootstrap serializer asks which organization is the user's default and
  # what their role is, and Sessions::TrackMetadata resolves the active
  # organization again at session commit. Each of those read the membership
  # list and the owner memberships afresh. A snapshot holds what one request
  # has read so far: the membership list, each organization's ownership and
  # membership record, and whatever a caller memoizes under a key (the
  # loader keeps the user's default organization there).
  #
  # The snapshots of a request live in a Fiber-local store that
  # Middleware::MembershipSnapshotContext opens and clears, the same
  # discipline as EntitlementPreview. With no store open (CLI, jobs, specs
  # that run no middleware) `for` hands out a fresh snapshot each time, so
  # nothing is reused outside a request. Nothing is kept across requests.
  #
  # A snapshot is dropped as soon as the request changes what it reflects:
  # Organization's membership writers (add, remove, activate), archive! and
  # unarchive!, and Customer#default_org_id= call `forget`. The next read in
  # that request starts from the datastore again.
  class MembershipSnapshot
    FIBER_KEY = :ots_membership_snapshots

    class << self
      # Open the request store. Any snapshot left by an earlier request on
      # this fiber is discarded.
      #
      # @return [void]
      def open
        Fiber[FIBER_KEY] = {}
      end

      # Clear the request store.
      #
      # @return [void]
      def close
        Fiber[FIBER_KEY] = nil
      end

      # @return [Boolean] whether a request store is open on this fiber
      def open?
        !Fiber[FIBER_KEY].nil?
      end

      # The request's snapshot for `customer`, created on first use. A fresh,
      # unshared snapshot when no store is open or the customer has no objid.
      #
      # @param customer [Onetime::Customer]
      # @return [MembershipSnapshot]
      def for(customer)
        store = Fiber[FIBER_KEY]
        key   = key_for(customer)
        return new(customer) if store.nil? || key.empty?

        store[key] ||= new(customer)
      end

      # Drop the request's snapshot for `customer`, if any. The next `for`
      # reads the datastore again.
      #
      # @param customer [Onetime::Customer, String] a customer or its objid
      # @return [void]
      def forget(customer)
        store = Fiber[FIBER_KEY]
        return if store.nil?

        store.delete(key_for(customer))
      end

      # Drop every snapshot in the request store.
      #
      # @return [void]
      def forget_all
        Fiber[FIBER_KEY] = {} unless Fiber[FIBER_KEY].nil?
      end

      private

      # The store key: an objid given as a string, or the customer's objid.
      # Empty for anything that cannot name itself, which is never stored.
      def key_for(customer)
        return customer if customer.is_a?(String)
        return '' unless customer.respond_to?(:objid)

        customer.objid.to_s
      end
    end

    attr_reader :customer

    def initialize(customer)
      @customer    = customer
      @owner       = {}
      @memberships = {}
      @memo        = {}
    end

    # Every organization the customer belongs to, archived ones included,
    # in membership order. Read once.
    #
    # @return [Array<Onetime::Organization>]
    def organizations
      @organizations ||= customer.organization_instances.to_a
    end

    # Organization#owner?(customer), read once per organization.
    #
    # @param org [Onetime::Organization]
    # @return [Boolean]
    def owner?(org)
      key = org.objid
      return @owner[key] if @owner.key?(key)

      @owner[key] = org.owner?(customer)
    end

    # The customer's membership record in `org`, read once per organization.
    #
    # @param org [Onetime::Organization]
    # @return [Onetime::OrganizationMembership, nil]
    def membership(org)
      key = org.objid
      return @memberships[key] if @memberships.key?(key)

      @memberships[key] = Onetime::OrganizationMembership.find_by_org_customer(org.objid, customer.objid)
    end

    # The block's value under `key`, computed once; nil is remembered too.
    #
    # @param key [Symbol]
    # @return [Object]
    def memo(key)
      return @memo[key] if @memo.key?(key)

      @memo[key] = yield
    end
  end
end
