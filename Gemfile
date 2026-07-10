# Gemfile
#
# frozen_string_literal: true
# typed: false

#
# Recommended: Ruby 3.4.7+
#   status: normal maintenance
#   release date: 2025-04-14
#   normal maintenance until: TBD
#   end of life: 2028-03 (est)
#
ruby file: '.ruby-version'

source 'https://rubygems.org/'

# ====================================
# Core Application Framework
# ====================================

gem 'otto', '~> 2.5'
gem 'rhales', '~> 0.6.2'
gem 'roda', '~> 3.0'
gem 'rodauth', '~> 2.0'
gem 'rodauth-omniauth', '~> 0.4'
gem 'rodauth-tools', '~> 0.4.0'

# OmniAuth providers (SSO via OIDC)
# NOTE: omniauth_openid_connect transitively pulls in activesupport (via
# openid_connect → activemodel, rack-oauth2, json-jwt, swd, webfinger). No
# ActiveSupport APIs are used by application code. email_validator and
# validate_url are also passengers from this chain.
gem 'omniauth-entra-id', '~> 3.1'
gem 'omniauth-github', '~> 2.0'
gem 'omniauth-google-oauth2', '~> 1.2'
gem 'omniauth_openid_connect', '~> 0.8'

# Web server and middleware
gem 'puma', '>= 6.0', '< 8.0'
gem 'rack', '>= 3.2.6', '< 4.0'
gem 'rack-contrib', '~> 2.5.0'
gem 'rack-protection', '~> 4.1'
gem 'rack-proxy', '~> 0.7'
gem 'rack-session', '~> 2.1.2'
gem 'rack-utf8_sanitizer'

# ====================================
# Data Processing & Utilities
# ====================================

# HTTP client
gem 'httparty'

# JSON and data validation
gem 'json_schemer'

# String and data processing
gem 'dry-cli', '~> 1.2'
gem 'fastimage', '~> 2.4'
gem 'i18n', '~> 1.14'
gem 'mail'
gem 'mustache'
gem 'public_suffix'
gem 'sanitize'
gem 'semantic_logger', '~> 4.17'
gem 'tilt'

# Email validation
gem 'truemail'

# ====================================
# Database & DB Tools
# ====================================

# ORMs and database drivers
# NOTE: We install both db drivers for the OCI images so that users can choose
# which database to use at runtime via environment variable without rebuilding.
# familia 2.11.2 floor: rejects a blank VERIFIABLE_ID_HMAC_SECRET at the library
# layer (delano/familia#335); the 2.11 line decouples the AES-256-GCM HKDF salt
# from the XChaCha20 personalization -- which activates the salt/personalization/
# history pinning in ConfigureFamilia; and 2.11.2 stops persisting nil declared
# fields as the JSON string "null" (HDEL on clear), restoring HSETNX/HEXISTS
# atomic-claim semantics (no migration -- stale "null" decodes to nil on read).
# Do NOT relax to 2.12: it lands breaking encryption personalization/salt-history
# changes (delano/familia#333, #334) that need the migration tracked in issue #3630.
gem 'familia', '~> 2.11.2'
gem 'pg', '~> 1.6'
gem 'sequel', '~> 5.0'
gem 'sqlite3', '~> 2.0'

# Redis/Valkey
gem 'redis', '~> 5.4.0'
gem 'uri-valkey', '~> 1.4.0'

# ====================================
# Security & Encryption
# ====================================

gem 'argon2', '~> 2.3'
gem 'bcrypt', '~> 3.1'
gem 'passforge', '~> 1.1'
# libsodium bindings. With rbnacl present, Familia's encrypted fields write
# XChaCha20-Poly1305 for new data (provider priority) while existing
# AES-256-GCM envelopes remain readable (algorithm recorded per envelope).
# Requires the libsodium shared library at runtime (see Dockerfile).
# MUST stay top-level: the production image sets
# BUNDLE_WITHOUT="development:test:optional", which would silently exclude
# it from any of those groups and quietly fall back to AES-256-GCM.
gem 'rbnacl', '~> 7.1', '>= 7.1.1'
gem 'rotp', '~> 6.2'
gem 'rqrcode', '~> 3.1'
gem 'webauthn', '~> 3.0'

# ====================================
# Ruby Standard Library Compatibility
# ====================================

gem 'base64'
gem 'irb'
gem 'logger'
gem 'psych', '~> 5.2.3'
gem 'rdoc'
gem 'reline'
gem 'stringio', '~> 3.1.6'

# ====================================
# Background Job Processing
# ====================================

gem 'bunny', '~> 2.22'           # RabbitMQ AMQP client
gem 'connection_pool', '~> 2.5'  # Thread-safe connection pooling
gem 'kicks', '~> 3.0'            # RabbitMQ worker framework (Sneakers successor)
gem 'rufus-scheduler', '~> 3.9'  # Cron-style job scheduling

# ====================================
# Third-Party Service Integrations
# ====================================

gem 'aws-sdk-sesv2', '~> 1.74', require: false
gem 'lettermint', '~> 0.2.0', require: false
gem 'sendgrid-ruby', require: false
gem 'sentry-ruby', require: false
gem 'stackprof', require: false
gem 'stripe', require: false

# ====================================
# Development & Testing Dependencies
# ====================================

group :development, :test do
  gem 'benchmark'
  gem 'database_cleaner-sequel', '~> 2.0'
  gem 'faker', '~> 3.2'
end

group :development do
  # Debugging tools
  gem 'debug', require: false
  gem 'htmlbeautifier', require: false
  gem 'rackup'
  gem 'rerun', '~> 0.14'

  # Code quality and language server
  gem 'kanayago', '~> 0.7', require: false
  gem 'rubocop', '~> 1.86.0', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-sequel', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'ruby-lsp', '~> 0.26.9', require: false
  gem 'solargraph', require: false # serena project index
  gem 'syntax_tree', require: false
end

group :test do
  # NOTE: FakeRedis removed due to redis 5.x incompatibility
  # See spec_helper.rb for details about mock_redis as future alternative
  gem 'bunny-mock', '~> 1.7', require: false  # Mock RabbitMQ for testing
  gem 'climate_control'
  gem 'rack-test', require: false
  gem 'rspec', '4.0.0.beta1'
  gem 'simplecov', require: false
  gem 'simplecov-cobertura', '~> 3.2', require: false # Cobertura XML output for GitHub Code Quality
  gem 'timecop', '~> 0.9'
  gem 'tryouts', '~> 3.7.1', require: false
  gem 'vcr', '~> 6.0'
  gem 'webmock', '~> 3.0'

  # RSpec components, pinned to match the rspec 4.0.0.beta1 release on rubygems.
  %w[rspec-core rspec-expectations rspec-mocks rspec-support].each do |lib|
    gem lib, '4.0.0.beta1'
  end
end
