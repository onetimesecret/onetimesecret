# apps/api/colonel/logic/colonel/ban_ip.rb
#
# frozen_string_literal: true

require 'ipaddr'
require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class BanIP < ColonelAPI::Logic::Base
        attr_reader :ip_address, :reason, :expiration, :banned_ip

        def process_params
          @ip_address = params['ip_address']
          @reason     = params['reason']
          @expiration = params['expiration'].to_i if params['expiration']

          raise_form_error('IP address is required', field: :ip_address) if ip_address.to_s.empty?

          # Validate IP address or CIDR format
          begin
            IPAddr.new(ip_address)
          rescue IPAddr::InvalidAddressError => e
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
          # Ban the IP
          @banned_ip = Onetime::BannedIP.ban!(
            ip_address,
            reason: reason,
            banned_by: cust.objid,
            expiration: expiration,
          )

          success_data
        end

        def success_data
          {
            record: {
              id: banned_ip.objid,
              ip_address: banned_ip.ip_address,
              reason: banned_ip.reason,
              banned_by: banned_ip.banned_by,
              banned_at: banned_ip.banned_at,
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
