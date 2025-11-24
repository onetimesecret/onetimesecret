# lib/onetime/boot/core_initializers.rb
#
# frozen_string_literal: true

require_relative 'initializer_registry'
require_relative '../initializers'

module Onetime
  module Boot
    # Register core system initializers with dependency ordering
    #
    # This file converts the existing initializers from lib/onetime/initializers/
    # into registry entries with explicit dependencies. The execution order is
    # determined automatically via TSort based on the provides/depends_on declarations.
    module CoreInitializers
      class << self
        def register_all
          # Load i18n locale files
          # Provides: :i18n capability for other initializers
          InitializerRegistry.register(
            name: :load_locales,
            description: 'Load i18n locale files',
            depends_on: [],
            provides: [:i18n]
          ) do |_ctx|
            Onetime.load_locales
          end

          # Setup SemanticLogger and application loggers
          # Provides: :logging capability
          InitializerRegistry.register(
            name: :setup_loggers,
            description: 'Initialize logging system',
            depends_on: [],
            provides: [:logging]
          ) do |_ctx|
            Onetime.setup_loggers
          end

          # Setup diagnostics (Sentry, monitoring)
          # Optional: Can fail without halting boot
          InitializerRegistry.register(
            name: :setup_diagnostics,
            description: 'Initialize diagnostics and monitoring',
            depends_on: [:logging],
            provides: [:diagnostics],
            optional: true
          ) do |_ctx|
            Onetime.setup_diagnostics
          end

          # Set application secrets from config
          # Provides: :secrets capability
          InitializerRegistry.register(
            name: :set_secrets,
            description: 'Configure application secrets',
            depends_on: [],
            provides: [:secrets]
          ) do |_ctx|
            Onetime.set_secrets
          end

          # Configure custom domains
          # Provides: :domains capability
          InitializerRegistry.register(
            name: :configure_domains,
            description: 'Configure custom domains',
            depends_on: [],
            provides: [:domains]
          ) do |_ctx|
            Onetime.configure_domains
          end

          # Configure email validation via Truemail
          # Provides: :email_validation capability
          InitializerRegistry.register(
            name: :configure_truemail,
            description: 'Configure email validation',
            depends_on: [],
            provides: [:email_validation]
          ) do |_ctx|
            Onetime.configure_truemail
          end

          # Configure Rhales HTTP client
          # Provides: :rhales capability
          InitializerRegistry.register(
            name: :configure_rhales,
            description: 'Configure HTTP client',
            depends_on: [],
            provides: [:rhales]
          ) do |_ctx|
            Onetime.configure_rhales
          end

          # Load fortune messages
          # Provides: :fortunes capability
          InitializerRegistry.register(
            name: :load_fortunes,
            description: 'Load fortune messages',
            depends_on: [],
            provides: [:fortunes]
          ) do |_ctx|
            Onetime.load_fortunes
          end

          # Setup database query logging
          # Note: Runs regardless of db connection
          InitializerRegistry.register(
            name: :setup_database_logging,
            description: 'Configure database query logging',
            depends_on: [:logging],
            provides: [:database_logging]
          ) do |_ctx|
            Onetime.setup_database_logging
          end

          # Configure Familia Redis ORM
          # Provides: :familia_config capability
          InitializerRegistry.register(
            name: :configure_familia,
            description: 'Configure Familia Redis ORM',
            depends_on: [:logging],
            provides: [:familia_config]
          ) do |_ctx|
            Onetime.configure_familia
          end

          # Detect and warn about legacy data in Redis
          # Must run after Familia is configured
          InitializerRegistry.register(
            name: :detect_legacy_data_and_warn,
            description: 'Detect legacy data in Redis',
            depends_on: [:familia_config],
            provides: [:legacy_check]
          ) do |_ctx|
            Onetime.detect_legacy_data_and_warn
          end

          # Setup Redis connection pool
          # Must run after legacy data detection
          # Provides: :database capability
          InitializerRegistry.register(
            name: :setup_connection_pool,
            description: 'Initialize Redis connection pool',
            depends_on: [:legacy_check],
            provides: [:database]
          ) do |_ctx|
            Onetime.setup_connection_pool
          end

          # Check for global banner message
          # Optional: Can fail without halting boot
          InitializerRegistry.register(
            name: :check_global_banner,
            description: 'Check for global banner message',
            depends_on: [:database],
            provides: [:banner],
            optional: true
          ) do |_ctx|
            Onetime.check_global_banner
          end

          # Print application boot banner
          # Runs last, depends on logging
          InitializerRegistry.register(
            name: :print_log_banner,
            description: 'Print application banner',
            depends_on: [:logging],
            provides: [:banner_printed],
            optional: true
          ) do |ctx|
            # Only print in TTY mode, not in test/cli
            if $stdout.tty? && !Onetime.mode?(:test) && !Onetime.mode?(:cli)
              Onetime.print_log_banner
            end
          end
        end
      end
    end
  end
end
