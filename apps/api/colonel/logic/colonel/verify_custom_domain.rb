# apps/api/colonel/logic/colonel/verify_custom_domain.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'domain_resolver'
require 'onetime/operations/admin_verify_domain'

module ColonelAPI
  module Logic
    module Colonel
      # Verify Custom Domain (Colonel)
      #
      # @api Runs DNS + SSL verification for a single custom domain, on demand,
      #   from the admin console — surfacing the CLI-only `bin/ots domains verify`
      #   capability in the UI (epic #31). Requires the colonel role.
      #
      # Thin adapter over {Onetime::Operations::AdminVerifyDomain}, which reuses the
      # incumbent {Onetime::Operations::VerifyDomain} (shared DNS/SSL verifier, no
      # duplication) and records the ColonelAuditEvent (CONTRACT 4). The response
      # reports the HONEST post-verification state (verified / resolving / pending /
      # unverified, plus any op error) — it never fakes success.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this logic
      # (verify_one_of_roles!(colonel: true)) enforce the colonel role. Unlike the
      # customer-facing DomainsAPI verify endpoint, the colonel resolves ANY domain
      # by its public extid with no organization-ownership check.
      class VerifyCustomDomain < ColonelAPI::Logic::Base
        include DomainResolver

        attr_reader :extid, :custom_domain, :result

        def process_params
          @extid = sanitize_identifier(params['extid'])
          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Resolve globally by PUBLIC id (extid) — the colonel domains list exposes
          # only extid. Colonel access is cross-organization, so (unlike GetDomain)
          # there is no ownership/membership gate here.
          @custom_domain = resolve_custom_domain(extid)
          raise_not_found('Domain not found') unless custom_domain
        end

        def process
          @result = Onetime::Operations::AdminVerifyDomain.new(
            domain: custom_domain,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            persist: true,
          ).call

          OT.info "[VerifyCustomDomain] #{custom_domain.display_domain} -> " \
                  "state=#{result.current_state}, dns=#{result.dns_validated}, indeterminate=#{result.dns_indeterminate}, " \
                  "resolving=#{result.is_resolving.inspect}"

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
              verified_by_override: custom_domain.verified_by_override == true,
              resolving: custom_domain.resolving.to_s == 'true',
              ready: custom_domain.ready?,
              updated: custom_domain.updated,
            },
            details: {
              previous_state: result.previous_state.to_s,
              current_state: result.current_state.to_s,
              changed: result.changed?,
              dns_validated: result.dns_validated,
              # true when the TXT check produced no answer; verified was left
              # unchanged unless dns_outcome is confirmation_expired (see
              # ConfirmationWindow). dns_message says which TXT outcome occurred.
              dns_indeterminate: result.dns_indeterminate,
              dns_message: result.dns_message,
              # validated / confirmation_expired / indeterminate / override_held /
              # failed — drives the operator notification when the state alone
              # would mislead. confirmation_expired: the check was indeterminate
              # and has been for longer than the confirmation window, so
              # verified was withdrawn.
              dns_outcome: result.dns_outcome.to_s,
              # true / false / nil. nil (JSON null) means this check could not
              # tell — provider status UNKNOWN, API or probe failure — and is
              # never sent as false. `record.resolving` above is the stored,
              # last known answer and stays a boolean.
              ssl_ready: result.ssl_ready,
              is_resolving: result.is_resolving,
              # nil on success; the op's captured error message on a check failure.
              error: result.error,
              message: 'Domain verification completed',
            },
          }
        end
      end
    end
  end
end
