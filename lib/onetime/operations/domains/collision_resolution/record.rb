# lib/onetime/operations/domains/collision_resolution/record.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    module Domains
      class CollisionResolution
        # The facts the rule reads for one record of a collision group, and
        # what the plan file stores for it.
        #
        # @!attribute org_state [r] Symbol — :missing (no organization, or
        #   the organization no longer exists), :archived, :active
        # @!attribute served [r] Boolean — a request for the group's DNS
        #   name (its A-label) resolves to this record today
        #   (CustomDomain.display_domain_id_for)
        # @!attribute verified_confirmed_at [r] Integer, nil — epoch seconds
        #   of the last passing TXT check (DNS proof)
        # @!attribute receipts [r] Integer — secrets shared under this record
        # @!attribute configs [r] Array<String> — per-domain config kinds that
        #   are never created automatically (sso, mailer) and exist
        # @!attribute all_configs [r] Array<String> — every config kind that
        #   exists, including the five an operator action can create disabled
        # @!attribute brand [r] Boolean — brand settings exist
        BILLING_FIELDS    = [:planid, :stripe_customer_id, :stripe_subscription_id, :subscription_status].freeze
        LIVE_STATUSES     = %w[active trialing past_due unpaid].freeze
        NOT_LIVE_STATUSES = %w[canceled incomplete incomplete_expired paused].freeze

        Record = Data.define(
          :domain_id,
          :extid,
          :display_domain,
          :org_id,
          :org_extid,
          :org_name,
          :org_state,
          :served,
          :verification_state,
          :ownership_verified,
          :verified_by_override,
          :verified_confirmed_at,
          :receipts,
          :configs,
          :all_configs,
          :brand,
          :vhost,
          :created,
          :planid,
          :stripe_customer_id,
          :stripe_subscription_id,
          :subscription_status,
        ) do
          def initialize(planid: nil, stripe_customer_id: nil, stripe_subscription_id: nil, subscription_status: nil, **attributes)
            super(
              **attributes, planid: planid, stripe_customer_id: stripe_customer_id,
                            stripe_subscription_id: stripe_subscription_id, subscription_status: subscription_status)
          end

          # These are cached facts, not a Stripe lookup or evidence of DNS control.
          # Unknown billing cannot silently authorize an automatic deletion.
          def billing_label
            return 'live_or_recoverable' if LIVE_STATUSES.include?(subscription_status.to_s)
            return 'not_live' if NOT_LIVE_STATUSES.include?(subscription_status.to_s)
            return 'no_local_subscription' if [subscription_status, stripe_customer_id, stripe_subscription_id].all? { |value| value.to_s.strip.empty? }

            'unknown'
          end

          def billing_protected?
            %w[live_or_recoverable unknown].include?(billing_label)
          end

          def billing_fingerprint
            BILLING_FIELDS.map { |field| public_send(field).to_s }
          end

          # Evidence that an organization uses the record: secrets shared
          # under it, brand settings, or a config that needs credentials.
          # The five materializable config kinds are not evidence (see
          # CustomDomain::ConfigRegistry::KINDS).
          def in_use?
            receipts.to_i.positive? || configs.any? || brand == true
          end

          def orphan?
            org_state == :missing
          end

          # The ownership flag was set by an operator override, not by a check.
          def override?
            verified_by_override == true
          end

          def dns_proof?
            !verified_confirmed_at.nil?
          end

          # The identifier an operator sees and types: the extid, or the
          # objid for a record whose hash carries none.
          def ref
            extid.to_s.empty? ? domain_id : extid
          end

          # Whether a reference from a plan file names this record.
          def named_by?(reference)
            value = reference.to_s
            !value.empty? && (value == domain_id || value == extid)
          end

          # What apply compares with the live record before writing.
          def fingerprint
            [display_domain.to_s, org_id.to_s, created.to_i]
          end

          # Normalize JSON round-trips without discarding any reviewed evidence.
          def evidence_fingerprint
            [domain_id.to_s, extid.to_s, *fingerprint, org_extid.to_s, org_name.to_s,
             served, verification_state.to_s, ownership_verified, verified_by_override,
             verified_confirmed_at&.to_s, receipts.to_i, configs.map(&:to_s).sort,
             all_configs.map(&:to_s).sort, brand, vhost]
          end

          def to_h
            super.merge(org_state: org_state.to_s, verification_state: verification_state.to_s)
          end

          # @param hash [Hash] a Record#to_h, with string or symbol keys
          def self.from_h(hash)
            h       = hash.transform_keys(&:to_sym)
            missing = BILLING_FIELDS - h.keys
            raise InvalidPlan, "record #{h[:extid] || h[:domain_id]} is missing billing fields: #{missing.join(', ')}; regenerate the plan" if missing.any?

            new(
              domain_id: h[:domain_id].to_s,
              extid: h[:extid],
              display_domain: h[:display_domain].to_s,
              org_id: h[:org_id],
              org_extid: h[:org_extid],
              org_name: h[:org_name],
              org_state: h[:org_state].to_s.empty? ? :missing : h[:org_state].to_sym,
              served: h[:served] == true,
              verification_state: h[:verification_state].to_s.empty? ? nil : h[:verification_state].to_sym,
              ownership_verified: h[:ownership_verified] == true,
              verified_by_override: h[:verified_by_override] == true,
              verified_confirmed_at: h[:verified_confirmed_at],
              receipts: h[:receipts].to_i,
              configs: Array(h[:configs]).map(&:to_s),
              all_configs: Array(h[:all_configs]).map(&:to_s),
              brand: h[:brand] == true,
              vhost: h[:vhost] == true,
              created: h[:created],
              **h.slice(*BILLING_FIELDS),
            )
          end
        end
      end
    end
  end
end
