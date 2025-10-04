#!/bin/bash
# Migration script for reorganizing tryouts tests
# Uses git mv to preserve file history

set -e  # Exit on error

echo "Starting tryouts reorganization..."

# Create directory structure using git mv's automatic parent creation
# Git will create parent directories as needed when moving files

# Phase 1: Move support files
echo "Phase 1: Moving support files..."
mkdir -p support
git mv test_helpers.rb support/
git mv test_logic.rb support/
git mv test_models.rb support/

# Phase 2: Move unit/models/v2 tests
echo "Phase 2: Moving model tests..."
mkdir -p unit/models/v2
git mv 20_metadata_try.rb unit/models/v2/metadata_try.rb
git mv 20_metadata_ttl_try.rb unit/models/v2/metadata_ttl_try.rb
git mv 21_secret_try.rb unit/models/v2/secret_try.rb
git mv 25_customer_try.rb unit/models/v2/customer_try.rb
git mv 30_session_try.rb unit/models/v2/session_try.rb
git mv 31_session_extended_try.rb unit/models/v2/session_extended_try.rb
git mv 23_app_settings_try.rb unit/models/v2/app_settings_try.rb

# Phase 3: Move unit/logic tests
echo "Phase 3: Moving logic tests..."
mkdir -p unit/logic/{authentication,secrets,account,domains}

# Base logic
git mv 60_logic/01_logic_base_try.rb unit/logic/base_try.rb
git mv 60_logic/02_logic_base_try.rb unit/logic/base_extended_try.rb

# Authentication
git mv 60_logic/02_logic_authentication_try.rb unit/logic/authentication/authenticate_session_try.rb

# Secrets
git mv 60_logic/03_logic_secrets_try.rb unit/logic/secrets/generate_secret_try.rb
git mv 60_logic/21_logic_secrets_show_metadata_try.rb unit/logic/secrets/show_metadata_try.rb
git mv 60_logic/22_logic_secrets_show_secret_try.rb unit/logic/secrets/show_secret_try.rb
git mv 60_logic/23_logic_secrets_reveal_secret_try.rb unit/logic/secrets/reveal_secret_try.rb

# Account
git mv 60_logic/04_logic_account_try.rb unit/logic/account/account_operations_try.rb
git mv 60_logic/24_logic_destroy_account_try.rb unit/logic/account/destroy_account_try.rb

# Domains (disabled)
mkdir -p disabled/domains
git mv 60_logic/40_logic_domains_try_disable.rb disabled/domains/logic_domains_try.rb
git mv 60_logic/41_logic_domains_add_try_disable.rb disabled/domains/logic_domains_add_try.rb

# Remove empty 60_logic directory
rmdir 60_logic 2>/dev/null || true

# Phase 4: Move unit/utils tests
echo "Phase 4: Moving utility tests..."
mkdir -p unit/utils
git mv 10_utils_try.rb unit/utils/utils_try.rb
git mv 10_utils_fortunes_try.rb unit/utils/fortunes_try.rb
git mv 19_safe_dump_try.rb unit/utils/safe_dump_try.rb
git mv 22_value_encryption_try.rb unit/utils/value_encryption_try.rb

# Phase 5: Move unit/config tests
echo "Phase 5: Moving config tests..."
mkdir -p unit/config
git mv 15_config_try.rb unit/config/config_try.rb
git mv 16_config_emailer_try.rb unit/config/emailer_config_try.rb
git mv 16_config_passphrase_options_try.rb unit/config/passphrase_options_try.rb
git mv 16_config_secret_options_try.rb unit/config/secret_options_try.rb
git mv 17_passphrase_validation_try.rb unit/config/passphrase_validation_try.rb
git mv 23_passphrase_try.rb unit/config/passphrase_try.rb
git mv 99_truemail_config_try.rb unit/config/truemail_config_try.rb

# Phase 6: Move integration/middleware tests
echo "Phase 6: Moving middleware integration tests..."
mkdir -p integration/middleware/domain_strategy

# Basic middleware
git mv 00_middleware/11_detect_host_try.rb integration/middleware/detect_host_try.rb
git mv 00_middleware/12_detect_host_instances_try.rb integration/middleware/detect_host_instances_try.rb
git mv 00_middleware/21_handle_invalid_percent_encoding_try.rb integration/middleware/handle_invalid_percent_encoding_try.rb
git mv 00_middleware/22_handle_invalid_utf8_try.rb integration/middleware/handle_invalid_utf8_try.rb

# Domain strategy middleware
git mv 50_middleware/20_domain_strategy_basics_try.rb integration/middleware/domain_strategy/basics_try.rb
git mv 50_middleware/21_domain_strategy_multiple_canonical_try.rb integration/middleware/domain_strategy/multiple_canonical_try.rb
git mv 50_middleware/22_domain_strategy_chooserator_try.rb integration/middleware/domain_strategy/chooserator_try.rb

# Disabled domain strategy
git mv 50_middleware/20_domain_strategy_try_disable.rb disabled/domains/domain_strategy_try.rb

# Remove empty middleware directories
rmdir 00_middleware 50_middleware 2>/dev/null || true

# Phase 7: Move integration/email tests
echo "Phase 7: Moving email integration tests..."
mkdir -p integration/email
git mv 40_email_template_try.rb integration/email/template_try.rb
git mv 40_email_template_locale_try.rb integration/email/template_locale_try.rb
git mv 68_receive_feedback_try.rb integration/email/receive_feedback_try.rb

# Phase 8: Move integration/authentication tests
echo "Phase 8: Moving authentication integration tests..."
mkdir -p integration/authentication
git mv 91_authentication_routes_try.rb integration/authentication/routes_try.rb

# Phase 9: Move integration/web tests
echo "Phase 9: Moving web integration tests..."
mkdir -p integration/web
git mv 42_web_template_vuepoint_try.rb integration/web/template_vuepoint_try.rb

# Phase 10: Move system/database tests
echo "Phase 10: Moving system database tests..."
mkdir -p system/database
git mv 80_database/10_redis_debug_try.rb system/database/redis_debug_try.rb
git mv 80_database/10_redis_key_migrator_basic_try.rb system/database/redis_key_migrator_basic_try.rb
git mv 80_database/20_redis_key_migrator_unit_try.rb system/database/redis_key_migrator_unit_try.rb
git mv 80_database/30_redis_key_migrator_integration_try.rb system/database/redis_key_migrator_integration_try.rb
git mv 80_database/20_database_logger_try.rb system/database/database_logger_try.rb
git mv 80_database/21_database_logger_demo_try.rb system/database/database_logger_demo_try.rb

# Remove empty database directory
rmdir 80_database 2>/dev/null || true

# Phase 11: Move system/initializers tests
echo "Phase 11: Moving initializer tests..."
mkdir -p system/initializers
git mv initializers/detect_legacy_data_try.rb system/initializers/detect_legacy_data_try.rb

# Remove empty initializers directory
rmdir initializers 2>/dev/null || true

# Phase 12: Move system tests
echo "Phase 12: Moving system tests..."
mkdir -p system
git mv 90_routes_smoketest_try.rb system/routes_smoketest_try.rb
git mv 05_logging_sync_try.rb system/logging_sync_try.rb

# Phase 13: Move disabled model tests
echo "Phase 13: Moving disabled model tests..."
# Disabled domains already handled, move the rest
git mv 20_models/27_domains_publicsuffix_try.rb disabled/domains/publicsuffix_try.rb
git mv 20_models/27_domains_expiration_try_disable.rb disabled/domains/expiration_try.rb
git mv 20_models/27_domains_try_disable.rb disabled/domains/domains_try.rb
git mv 20_models/27_domains_methods_try_disable.rb disabled/domains/methods_try.rb
git mv 20_models/28_domains_verification_try_disable.rb disabled/domains/verification_try.rb
git mv 20_models/29_customer_domains_try_disable.rb disabled/domains/customer_domains_try.rb

# Remove empty models directory
rmdir 20_models 2>/dev/null || true

# Phase 14: Move experimental/misc tests
echo "Phase 14: Moving experimental tests..."
mkdir -p experimental
git mv 72_approximated.rb experimental/approximated_try.rb
git mv 05_logging.rb experimental/logging_demo.rb
git mv 17_mail_validation.rb experimental/mail_validation.rb

echo ""
echo "Migration complete!"
echo ""
echo "Summary of new structure:"
echo "  unit/          - Fast, isolated unit-like tests"
echo "  integration/   - Multi-component integration tests"
echo "  system/        - Full system tests"
echo "  disabled/      - Temporarily disabled tests"
echo "  experimental/  - Experimental/demo code"
echo "  support/       - Test helpers and fixtures"
echo ""
echo "Next steps:"
echo "  1. Update require paths in moved files"
echo "  2. Run: FAMILIA_DEBUG=0 bundle exec try --agent"
echo "  3. Fix any broken require paths"
