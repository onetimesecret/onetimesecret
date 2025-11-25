# apps/api/account/logic/colonel/list_banned_ips.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      class ListBannedIPs < ColonelAPI::Logic::Base
        attr_reader :banned_ips, :total_count

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Get all banned IPs
          all_banned_ips_ids = Onetime::BannedIP.instances.to_a
          all_banned_ips     = Onetime::BannedIP.load_multi(all_banned_ips_ids).compact

          @total_count = all_banned_ips.size

          # Sort by banned_at (most recent first)
          all_banned_ips.sort_by! { |ip| -(ip.banned_at || 0) }

          @banned_ips = all_banned_ips.map do |banned_ip|
            {
              id: banned_ip.objid,
              ip_address: banned_ip.ip_address,
              reason: banned_ip.reason,
              banned_by: banned_ip.banned_by,
              banned_at: banned_ip.banned_at,
              banned_at_human: natural_time(banned_ip.banned_at),
            }
          end

          success_data
        end

        def success_data
          # Get IP from strategy_result metadata or session
          client_ip = @strategy_result.metadata[:ip] ||
                      @strategy_result.metadata['ip'] ||
                      sess['ip_address'] ||
                      'unknown'

          {
            record: {},
            details: {
              current_ip: client_ip,
              banned_ips: banned_ips,
              total_count: total_count,
            },
          }
        end
      end
    end
  end
end
