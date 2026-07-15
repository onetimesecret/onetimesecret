# apps/api/colonel/logic/colonel/ban_ip.rb
#
# frozen_string_literal: true

require 'ipaddr'
require_relative '../base'
require 'onetime/operations/ban_ip'

module ColonelAPI
  module Logic
    module Colonel
      # Ban an IP address / CIDR (Colonel).
      #
      # Thin adapter over {Onetime::Operations::BanIP} — the single, audited
      # implementation of the ban verb (epic #33). This class keeps only the HTTP
      # concerns (param validation + the already-banned form error); the op owns
      # the model mutation and the AdminAuditEvent (CONTRACT 4).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class BanIP < ColonelAPI::Logic::Base
        attr_reader :ip_address, :reason, :expiration, :result

        def process_params
          @ip_address = sanitize_ip_address(params['ip_address'])
          @reason     = sanitize_plain_text(params['reason'], max_length: 255)
          @expiration = params['expiration'].to_i if params['expiration']

          raise_form_error('IP address is required', field: :ip_address) if ip_address.to_s.empty?

          # Validate IP address or CIDR format
          begin
            IPAddr.new(ip_address)
          rescue IPAddr::InvalidAddressError
            raise_form_error('Invalid IP address or CIDR format', field: :ip_address)
          end
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Check if already banned
          if Onetime::BannedIP.banned?(ip_address)
            raise_form_error('IP address is already banned', field: :ip_address)
          end
        end

        def process
          # Delegate the model mutation + audit to the single op implementation.
          # banned_by keeps the historic value (acting colonel's objid) for
          # bit-for-bit parity with the prior inline call; actor is the colonel's
          # PUBLIC id, used only for the audit trail (never an objid).
          @result = Onetime::Operations::BanIP.new(
            ip_address: ip_address,
            reason: reason,
            banned_by: cust.objid,
            actor: cust.extid,
            expiration: expiration,
          ).call

          success_data
        end

        def success_data
          {
            record: {
              id: result.id,
              ip_address: result.ip_address,
              reason: result.reason,
              banned_by: result.banned_by,
              banned_at: result.banned_at,
            },
            details: {
              message: 'IP address banned successfully',
            },
          }
        end
      end
    end
  end
end
