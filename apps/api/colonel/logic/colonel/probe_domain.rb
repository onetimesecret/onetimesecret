# apps/api/colonel/logic/colonel/probe_domain.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/domains/probe'

module ColonelAPI
  module Logic
    module Colonel
      # Probe a custom domain (Colonel) — make an HTTPS request to confirm the
      # domain serves traffic + inspect its TLS certificate, surfacing the
      # CLI-only `bin/ots domains probe` toolbox (epic #43).
      #
      # Thin adapter over {Onetime::Operations::Domains::Probe} — the single
      # implementation of the probe verb. The op owns the outbound request +
      # health taxonomy; this class resolves the domain by public extid.
      #
      # READ-ONLY: probing reaches the network but mutates nothing in our store, so
      # it records NO AdminAuditEvent (CONTRACT 4).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role. The
      # colonel resolves ANY domain by its public extid with no ownership check.
      class ProbeDomain < ColonelAPI::Logic::Base
        # Clamp the operator-supplied timeout so a probe can't hang the request
        # path indefinitely; matches the CLI default of 10s.
        MAX_TIMEOUT     = 30
        DEFAULT_TIMEOUT = 10

        attr_reader :extid, :custom_domain, :timeout, :result

        def process_params
          @extid   = sanitize_identifier(params['extid'])
          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?

          @timeout = (params['timeout'] || DEFAULT_TIMEOUT).to_i
          @timeout = DEFAULT_TIMEOUT if @timeout <= 0
          @timeout = MAX_TIMEOUT if @timeout > MAX_TIMEOUT
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @custom_domain = Onetime::CustomDomain.find_by_extid(extid)
          raise_not_found('Domain not found') unless custom_domain
        end

        def process
          # Colonel probes always verify TLS (no insecure flag exposed over HTTP).
          @result = Onetime::Operations::Domains::Probe.new(
            hostname: custom_domain.display_domain,
            timeout: timeout,
            insecure: false,
          ).call

          OT.info "[ProbeDomain] #{custom_domain.display_domain} -> health=#{result[:health]}"

          success_data
        end

        def success_data
          {
            record: {
              extid: custom_domain.extid,
              display_domain: custom_domain.display_domain,
            },
            details: {
              timestamp: result[:timestamp],
              domain: result[:domain],
              url: result[:url],
              http: result[:http],
              ssl: result[:ssl],
              health: result[:health],
            },
          }
        end
      end
    end
  end
end
