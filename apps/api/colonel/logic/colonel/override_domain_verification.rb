# apps/api/colonel/logic/colonel/override_domain_verification.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/models/colonel_audit_event'

module ColonelAPI
  module Logic
    module Colonel
      # Override Domain Verification (Colonel)
      #
      # @api Manually override the verified/resolving flags on a custom domain
      #   without running DNS checks. This is an administrative escape hatch for
      #   situations where DNS verification cannot complete normally (e.g., private
      #   networks, DNS propagation delays, or manual verification by operator).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this logic
      # (verify_one_of_roles!(colonel: true)) enforce the colonel role. Unlike the
      # customer-facing DomainsAPI verify endpoint, the colonel resolves ANY domain
      # by its public extid with no organization-ownership check.
      #
      # Both params are optional: the colonel may flip only one flag, leaving the
      # other unchanged. The audit trail records the previous and new values.
      class OverrideDomainVerification < ColonelAPI::Logic::Base
        AUDIT_VERB = 'domain.override_verification'

        attr_reader :extid,
          :custom_domain,
          :verified_param,
          :resolving_param,
          :previous_verified,
          :previous_resolving

        def process_params
          @extid = sanitize_identifier(params['extid'])
          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?

          # Both are optional; nil means "do not change"
          @verified_param  = parse_optional_boolean(params['verified'], field: :verified)
          @resolving_param = parse_optional_boolean(params['resolving'], field: :resolving)

          # At least one flag must be provided
          if verified_param.nil? && resolving_param.nil?
            raise_form_error('At least one of verified or resolving must be provided')
          end
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @custom_domain = Onetime::CustomDomain.find_by_extid(extid)
          raise_not_found('Domain not found') unless custom_domain
        end

        def process
          # Capture previous state for audit trail
          @previous_verified  = custom_domain.verified.to_s == 'true'
          @previous_resolving = custom_domain.resolving.to_s == 'true'

          # Apply changes atomically
          custom_domain.atomic_write do
            custom_domain.verified  = verified_param unless verified_param.nil?
            custom_domain.resolving = resolving_param unless resolving_param.nil?
            custom_domain.updated   = OT.now.to_i
          end

          record_audit_event

          OT.info "[OverrideDomainVerification] #{custom_domain.display_domain} -> " \
                  "verified=#{custom_domain.verified}, resolving=#{custom_domain.resolving} " \
                  "by #{cust.extid}"

          success_data
        end

        def success_data
          {
            record: {
              domain_id: custom_domain.domainid,
              extid: custom_domain.extid,
              display_domain: custom_domain.display_domain,
              verification_state: custom_domain.verification_state.to_s,
              verified: custom_domain.verified.to_s == 'true',
              resolving: custom_domain.resolving.to_s == 'true',
              ready: custom_domain.ready?,
              updated: custom_domain.updated,
            },
            details: {
              previous_verified: previous_verified,
              previous_resolving: previous_resolving,
              current_verified: custom_domain.verified.to_s == 'true',
              current_resolving: custom_domain.resolving.to_s == 'true',
              verified_changed: (custom_domain.verified.to_s == 'true') != previous_verified,
              resolving_changed: (custom_domain.resolving.to_s == 'true') != previous_resolving,
              message: 'Domain verification flags overridden',
            },
          }
        end

        private

        def record_audit_event
          Onetime::ColonelAuditEvent.record(
            actor: cust.extid,
            verb: AUDIT_VERB,
            target: custom_domain.extid,
            result: :success,
            detail: {
              previous_verified: previous_verified,
              previous_resolving: previous_resolving,
              new_verified: verified_param.nil? ? '(unchanged)' : verified_param,
              new_resolving: resolving_param.nil? ? '(unchanged)' : resolving_param,
              current_state: custom_domain.verification_state.to_s,
            },
          )
        end

        # Parse an optional boolean parameter.
        # Returns true, false, or nil (when param is absent or blank).
        # Any other value is rejected loudly: silently coercing garbage
        # (e.g. "maybe") to false could clear a manually-verified domain.
        def parse_optional_boolean(value, field:)
          return nil if value.nil?
          return nil if value.to_s.strip.empty?

          normalized = value.to_s.strip.downcase
          return true  if %w[true 1 yes on].include?(normalized)
          return false if %w[false 0 no off].include?(normalized)

          raise_form_error("Invalid boolean value for #{field}: #{value.inspect}", field: field)
        end
      end
    end
  end
end
