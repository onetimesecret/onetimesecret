# apps/api/colonel/logic/colonel/unban_ip.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/unban_ip'

module ColonelAPI
  module Logic
    module Colonel
      # Unban an IP address / CIDR (Colonel).
      #
      # Thin adapter over {Onetime::Operations::UnbanIP} — the single, audited
      # implementation of the unban verb (epic #33). This class keeps only the
      # HTTP concerns (param validation + the not-banned 404); the op owns the
      # model mutation and the AdminAuditEvent (CONTRACT 4).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class UnbanIP < ColonelAPI::Logic::Base
        attr_reader :ip_address, :unbanned

        def process_params
          @ip_address = sanitize_ip_address(params['ip'])
          raise_form_error('IP address is required', field: :ip) if ip_address.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Check if IP is actually banned
          unless Onetime::BannedIP.banned?(ip_address)
            raise_not_found('IP address is not banned')
          end
        end

        def process
          # Delegate the model mutation + audit to the single op implementation.
          # actor is the acting colonel's PUBLIC id (never an objid).
          result   = Onetime::Operations::UnbanIP.new(
            ip_address: ip_address,
            actor: cust.extid,
          ).call
          @unbanned = result.unbanned

          success_data
        end

        def success_data
          {
            record: {
              ip_address: ip_address,
              unbanned: unbanned,
            },
            details: {
              message: 'IP address unbanned successfully',
            },
          }
        end
      end
    end
  end
end
