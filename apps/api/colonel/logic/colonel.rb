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

# Entitlement preview mode
require_relative 'colonel/get_available_plans'
require_relative 'colonel/set_entitlement_preview'

# Secret management
require_relative 'colonel/list_secrets'
require_relative 'colonel/get_secret_receipt'
require_relative 'colonel/delete_secret'

# User management
require_relative 'colonel/list_users'
require_relative 'colonel/get_user_details'
require_relative 'colonel/update_user_plan'
require_relative 'colonel/set_user_role'
require_relative 'colonel/set_user_verification'
require_relative 'colonel/purge_user'

# System monitoring
require_relative 'colonel/get_database_metrics'
require_relative 'colonel/get_redis_metrics'

# IP banning
require_relative 'colonel/list_banned_ips'
require_relative 'colonel/ban_ip'
require_relative 'colonel/unban_ip'

# Custom domains
require_relative 'colonel/list_custom_domains'
require_relative 'colonel/verify_custom_domain'

# Organizations
require_relative 'colonel/list_organizations'
require_relative 'colonel/investigate_organization'
require_relative 'colonel/manage_entitlement_override'

# Usage export
require_relative 'colonel/export_usage'

# Queue metrics (RabbitMQ)
require_relative 'colonel/get_queue_metrics'
