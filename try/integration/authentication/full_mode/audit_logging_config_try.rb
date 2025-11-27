# try/integration/authentication/advanced_mode/audit_logging_config_try.rb
#
# frozen_string_literal: true

require_relative '../../../support/test_helpers'

# Load Auth module
require_relative '../../../../apps/web/auth/config'

# ============================================================================
# Audit Logging Configuration Tests
# ============================================================================
#
# These tests verify the audit logging feature is properly configured.
#

## Audit logging feature is enabled
Auth::Config.allocate.features.include?(:audit_logging)
#=> true

## Audit logging table is configured
Auth::Config.allocate.audit_logging_table
#=> :account_authentication_audit_logs

## Audit logging account_id column is configured
Auth::Config.allocate.audit_logging_account_id_column
#=> :account_id

## Audit logging message column is configured
Auth::Config.allocate.audit_logging_message_column
#=> :message

## Audit logging metadata column is configured
Auth::Config.allocate.audit_logging_metadata_column
#=> :metadata
