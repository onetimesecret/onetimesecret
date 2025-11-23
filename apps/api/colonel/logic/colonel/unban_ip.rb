# apps/api/account/logic/colonel/unban_ip.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class UnbanIP < ColonelAPI::Logic::Base
        attr_reader :ip_address, :unbanned

        def process_params
          @ip_address = params['ip']
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
          # Unban the IP
          @unbanned = Onetime::BannedIP.unban!(ip_address)

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
