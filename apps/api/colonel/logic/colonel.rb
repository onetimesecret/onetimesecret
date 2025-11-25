# apps/api/colonel/logic/colonel.rb
#
# frozen_string_literal: true

require_relative 'base'

module ColonelAPI
  module Logic
    module Colonel
    end
  end
end

# System info and stats
require_relative 'colonel/get_colonel_info'
require_relative 'colonel/get_colonel_stats'
require_relative 'colonel/get_system_settings'

# Secret management
require_relative 'colonel/list_secrets'
require_relative 'colonel/get_secret_metadata'
require_relative 'colonel/delete_secret'

# User management
require_relative 'colonel/list_users'
require_relative 'colonel/get_user_details'
require_relative 'colonel/update_user_plan'

# System monitoring
require_relative 'colonel/get_database_metrics'
require_relative 'colonel/get_redis_metrics'

# IP banning
require_relative 'colonel/list_banned_ips'
require_relative 'colonel/ban_ip'
require_relative 'colonel/unban_ip'

# Custom domains
require_relative 'colonel/list_custom_domains'

# Usage export
require_relative 'colonel/export_usage'
