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
require_relative 'colonel/set_user_suspension'
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
require_relative 'colonel/create_custom_domain'
require_relative 'colonel/get_custom_domain'
require_relative 'colonel/remove_custom_domain'

# Organizations
require_relative 'colonel/list_organizations'
require_relative 'colonel/get_organization_detail'
require_relative 'colonel/investigate_organization'
require_relative 'colonel/reconcile_organization'
require_relative 'colonel/manage_entitlement_override'

# Usage export
require_relative 'colonel/export_usage'

# Queue metrics (RabbitMQ)
require_relative 'colonel/get_queue_metrics'

# Sessions (ticket #40)
require_relative 'colonel/list_sessions'
require_relative 'colonel/get_session_detail'
require_relative 'colonel/delete_session'

# Per-customer sessions view — sidecar-backed (spec 40-sessions-metadata-sidecar)
require_relative 'colonel/list_customer_sessions'
require_relative 'colonel/revoke_customer_session'
require_relative 'colonel/revoke_all_customer_sessions'

# Broadcast banner (ticket #41)
require_relative 'colonel/get_banner'
require_relative 'colonel/set_banner'
require_relative 'colonel/clear_banner'

# Queue DLQ console (ticket #42)
require_relative 'colonel/list_dlqs'
require_relative 'colonel/get_dlq_messages'
require_relative 'colonel/replay_dlq'
require_relative 'colonel/purge_dlq'

# Domain toolbox (ticket #43)
require_relative 'colonel/list_orphaned_domains'
require_relative 'colonel/probe_domain'
require_relative 'colonel/repair_domain'
require_relative 'colonel/transfer_domain'

# Email + rate-limit tools (ticket #44)
require_relative 'colonel/list_email_templates'
require_relative 'colonel/preview_email_template'
require_relative 'colonel/send_test_email'
require_relative 'colonel/get_email_config'
require_relative 'colonel/list_rate_limiters'
require_relative 'colonel/inspect_rate_limit'
require_relative 'colonel/reset_rate_limit'

# Email deliverability (bounces / complaints / suppression list)
require_relative 'colonel/get_email_deliverability'
require_relative 'colonel/list_email_suppressions'
require_relative 'colonel/add_email_suppression'
require_relative 'colonel/remove_email_suppression'
require_relative 'colonel/list_email_deliverability_events'
require_relative 'colonel/ingest_email_deliverability_events'
require_relative 'colonel/sync_email_deliverability'
require_relative 'colonel/get_email_provider_status'
require_relative 'colonel/lookup_email_recipient'
require_relative 'colonel/list_email_messages'

# Billing catalog (ticket #45)
require_relative 'colonel/get_billing_catalog'

# Observability: audit trail reader + daily activity trends
require_relative 'colonel/list_audit_events'
require_relative 'colonel/get_trends'
