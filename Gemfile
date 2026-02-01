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
ruby '>= 3.4.7'

source 'https://rubygems.org/'

# ====================================
# Core Application Framework
# ====================================

gem 'otto', '~> 2.0.0.pre10'
gem 'rhales', '~> 0.5.4'
gem 'roda', '~> 3.0'
gem 'rodauth', '~> 2.0'
gem 'rodauth-omniauth', '~> 0.4'
gem 'rodauth-tools', '~> 0.3.1'

# OmniAuth providers (SSO via OIDC)
gem 'omniauth_openid_connect', '~> 0.8'

# Web server and middleware
gem 'puma', '>= 6.0', '< 8.0'
gem 'rack', '>= 3.2', '< 4.0'
gem 'rack-contrib', '~> 2.5.0'
gem 'rack-protection', '~> 4.1'
gem 'rack-proxy', '~> 0.7'
gem 'rack-session', '~> 2.1.1'
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
gem 'familia', path: '../d/familia'
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
gem 'encryptor', '= 1.1.3'
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
gem 'connection_pool', '~> 2.4'  # Thread-safe connection pooling
gem 'kicks', '~> 3.0'            # RabbitMQ worker framework (Sneakers successor)
gem 'rufus-scheduler', '~> 3.9'  # Cron-style job scheduling

# ====================================
# Third-Party Service Integrations
# ====================================

gem 'aws-sdk-sesv2', '~> 1.74', require: false
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
  gem 'rubocop', '~> 1.81.7', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-sequel', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'ruby-lsp', require: false
  gem 'solargraph', require: false # serena project index
  gem 'syntax_tree', require: false
end

group :test do
  # NOTE: FakeRedis removed due to redis 5.x incompatibility
  # See spec_helper.rb for details about mock_redis as future alternative
  gem 'bunny-mock', '~> 1.7', require: false  # Mock RabbitMQ for testing
  gem 'climate_control'
  gem 'rack-test', require: false
  gem 'rspec', git: 'https://github.com/rspec/rspec'
  gem 'simplecov', require: false
  gem 'timecop', '~> 0.9'
  gem 'tryouts', '~> 3.7.1', require: false
  gem 'vcr', '~> 6.0'
  gem 'webmock', '~> 3.0'

  # RSpec components
  %w[rspec-core rspec-expectations rspec-mocks rspec-support].each do |lib|
    gem lib, git: 'https://github.com/rspec/rspec', glob: "#{lib}/#{lib}.gemspec"
  end
end

# ====================================
# Optional Dependencies
# ====================================

# Optional alternate server - install with: bundle install --with optional
group :optional do
  gem 'thin'
end
