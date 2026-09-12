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

# 2.8+: depth mode records a forwarded-host trust signal (delano/otto#226),
# and otto.via_trusted_proxy is tri-state — written only when proxy trust is
# configured (present => authoritative, absent => legacy heuristics apply).
# 2.8.1+: opt-in ASN (req.asn) and anonymizer (req.anonymizer) enrichment,
# both off by default and database-only — no behavior change until a
# *_db_path is configured (delano/otto docs/enrichment.md).
# 2.9 floor: request-scoped CSP directive extras via
# env['otto.csp.extra_directives'] (delano/otto#243), consumed by
# Onetime::Middleware::TenantCspExtras (#4173).
# 2.10 floor: forwarded-authority hardening (delano/otto#252, #259).
# IPPrivacyMiddleware strips Forwarded / X-Forwarded-{Host,Proto,Scheme,SSL,Port}
# from untrusted peers, and Otto::Security::Config#trusted_proxy_header= pins
# Rack::Request.forwarded_priority process-wide — the app sets the header
# unconditionally in MiddlewareStack.ip_privacy_security_config so Rack never
# reads RFC 7239 Forwarded for host/port/proto. rack-parser stopped being an
# otto runtime dependency in 2.10; it is declared below.
gem 'otto', '~> 2.10'
gem 'rhales', '~> 0.7.1'
gem 'roda', '~> 3.0'
gem 'rodauth', '~> 2.0'
gem 'rodauth-omniauth', '~> 0.4'
gem 'rodauth-tools', '~> 0.4.0'

# OmniAuth providers (SSO via OIDC)
# NOTE: omniauth_openid_connect transitively pulls in activesupport (via
# openid_connect → activemodel, rack-oauth2, json-jwt, swd, webfinger). No
# ActiveSupport APIs are used by application code. validate_url is also a
# passenger from this chain.
gem 'omniauth-entra-id', '~> 3.1'
gem 'omniauth-github', '~> 2.0'
gem 'omniauth-google-oauth2', '~> 1.2'
gem 'omniauth_openid_connect', '~> 0.8'

# Web server and middleware
gem 'puma', '>= 6.0', '< 8.0'
gem 'rack', '>= 3.2.6', '< 4.0'
gem 'rack-contrib', '~> 2.5.0'
# Mounted directly in MiddlewareStack (JSON/form body parsing); was transitive via otto < 2.10.
gem 'rack-parser', '~> 0.7'
gem 'rack-protection', '~> 4.1'
gem 'rack-proxy', '~> 0.7'
gem 'rack-session', '~> 2.1.2'
gem 'rack-utf8_sanitizer', '~> 1.11'

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
gem 'public_suffix', '~> 7.0'
gem 'sanitize', '~> 7.0'
gem 'semantic_logger', '~> 4.17'
gem 'tilt'

# Email validation
gem 'truemail', '~> 3.3'

# ====================================
# Database & DB Tools
# ====================================

# ORMs and database drivers
# NOTE: We install both db drivers for the OCI images so that users can choose
# which database to use at runtime via environment variable without rebuilding.
# familia 2.12 floor: read-side prep for the encryption rotation tracked in
# issue #3630. 2.12.0 adds encryption_personalization_history (delano/familia#333)
# so XChaCha20 decrypt walks current -> history -> the library default
# 'FamilialMatters', making personalization rotatable without stranding old
# envelopes; per-field `algorithm:` pinning (delano/familia#334, shipped 2.11.1)
# plus envelope-driven provider dispatch means readers accept both aes-256-gcm
# and xchacha20poly1305 ciphertext with zero configuration. This release changes
# nothing on the write side -- ConfigureFamilia still pins the 2.11-era values
# byte-for-byte; the write-side rotation flip lands in v0.27.0 and requires
# every process reading the datastore to be on >= this release first.
# (2.11.2 remains the behavior floor for blank VERIFIABLE_ID_HMAC_SECRET
# rejection, delano/familia#335, and for nil declared fields persisting as HDEL
# instead of the JSON string "null".)
gem 'familia', '~> 2.12'
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
# Needed by the OPTIONAL audit syslog appender (#4334,
# etc/defaults/logging.defaults.yaml `audit.syslog`). Declared here for the same
# reason as its neighbours: `syslog` became a BUNDLED gem in Ruby 3.4, so
# Bundler blocks `require 'syslog'` unless the Gemfile names it — the appender
# would raise LoadError the moment an operator enabled it. No third-party code:
# this ships with Ruby.
gem 'syslog'

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
# Pin to 18.x: stripe 19 pins API version 2026-06-24.dahlia (sent on every
# request), which moves Subscription#current_period_start/end onto items and
# converts decimal_string fields to BigDecimal. Migrating is a separate effort.
gem 'stripe', '~> 18.4', require: false

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
  gem 'rubocop', '~> 1.89.0', require: false
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
  gem 'tryouts', '~> 4.0.0.pre1', require: false
  gem 'vcr', '~> 6.0'
  gem 'webmock', '~> 3.0'

  # RSpec components, pinned to match the rspec 4.0.0.beta1 release on rubygems.
  %w[rspec-core rspec-expectations rspec-mocks rspec-support].each do |lib|
    gem lib, '4.0.0.beta1'
  end
end
