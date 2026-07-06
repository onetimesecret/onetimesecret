# apps/web/auth/operations/customers/show.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    module Customers
      # Resolve a single customer and gather its detail view (core attributes +
      # organizations) for the admin surfaces.
      #
      # The ONE implementation of "look up a customer for an admin and describe it."
      # Read-only, so it writes no audit event. Resolution accepts a public
      # identifier (extid or email) or an internal objid, or a pre-resolved
      # Customer instance.
      #
      # Note on resolution scope: this op resolves extid / email / objid — the forms
      # every admin surface shares. The CLI's numeric Rodauth-account-id lookup
      # stays in the CLI (`Customers::Shared#resolve_customer`) because it is an
      # auth-mode-specific SQL concern (accounts.id -> external_id) that does not
      # belong in a Redis-only domain op.
      class Show
        # Immutable result. `customer` is nil when nothing resolved (found? false).
        Result = Data.define(:customer, :organizations) do
          def found?
            !customer.nil?
          end
        end

        # @param identifier [String, nil] extid, email, or objid
        # @param customer [Onetime::Customer, nil] a pre-resolved customer
        #   (takes precedence over identifier)
        def initialize(identifier: nil, customer: nil)
          @identifier = identifier
          @customer   = customer
        end

        # @return [Result]
        def call
          customer = @customer || resolve(@identifier)

          unless customer && customer.exists?
            return Result.new(customer: nil, organizations: [])
          end

          Result.new(customer: customer, organizations: gather_organizations(customer))
        end

        private

        # Resolve extid -> email -> objid. Returns nil when nothing matches.
        def resolve(identifier)
          normalized = identifier.to_s.strip
          return nil if normalized.empty?

          # extid / email first (public identifiers), then objid as a fallback.
          Onetime::Customer.load_by_extid_or_email(normalized) ||
            Onetime::Customer.load(normalized)
        end

        # Summarize the customer's organizations. Uses the customer's own
        # organization_instances relationship (no cross-customer enumeration).
        def gather_organizations(customer)
          return [] unless customer.respond_to?(:organization_instances)

          customer.organization_instances.to_a.compact.map do |org|
            {
              objid: org.objid,
              extid: org.extid,
              display_name: org.display_name,
            }
          end
        end
      end
    end
  end
end
