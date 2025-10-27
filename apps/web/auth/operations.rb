# apps/web/auth/operations.rb

require_relative 'operations/sync_session'
require_relative 'operations/update_password_metadata'
require_relative 'operations/create_customer'
require_relative 'operations/delete_customer'
require_relative 'operations/verify_customer'
require_relative 'operations/disable_mfa'
require_relative 'operations/detect_mfa_requirement'
require_relative 'operations/process_mfa_recovery'
