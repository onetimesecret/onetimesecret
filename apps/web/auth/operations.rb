# apps/web/auth/operations.rb
#
# frozen_string_literal: true

require_relative 'operations/sync_session'
require_relative 'operations/update_password_metadata'
require_relative 'operations/create_customer'
require_relative 'operations/delete_customer'
require_relative 'operations/verify_customer'
require_relative 'operations/disable_mfa'
require_relative 'operations/detect_mfa_requirement'
require_relative 'operations/mfa_state_checker'
require_relative 'operations/prepare_mfa_session'
