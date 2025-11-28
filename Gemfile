# Gemfile
#
# frozen_string_literal: true

# Recommended: Ruby 3.4+
#
# status: normal maintenance
# release date: 2024-12-25
# normal maintenance until: TBD
# end of life: 2028ish
#
# We support versions of Ruby that are still in normal maintenance.
#
ruby '>= 3.1.5'

source 'https://rubygems.org/'

# ====================================
# Core Application Framework
# ====================================

gem 'altcha', '~> 0.2.1'

gem 'otto', '~> 1.1.0.pre.alpha4'

gem 'rack', '>= 2.2.12', '< 3.0'
gem 'rack-contrib', '~> 2.5'
gem 'rack-protection', '~> 3.2'
gem 'rack-utf8_sanitizer', '~> 1.10.1'
gem 'thin'

gem 'drydock'
gem 'gibbler'
gem 'storable'
gem 'sysinfo'
gem 'tty-table', '~> 0.12.0'

# ====================================
# Data Processing & Utilities
# ====================================

# HTTP client
gem 'dotenv'
gem "fastimage", "~> 2.4"
gem 'httparty'
gem 'mail'
gem 'mustache'
gem 'multi_json'
gem 'public_suffix'
gem 'net-imap', '~> 0.5.7'
gem 'truemail'

# ====================================
# Database & DB Tools
# ====================================

gem 'familia', '~> 1.2.3'

# Redis/Valkey
gem 'redis', '~> 5.4.0'
gem 'uri-valkey', '~> 1.4.0'

# ====================================
# Security & Encryption
# ====================================

gem 'bcrypt', '~> 3.1'
gem 'encryptor', '= 1.1.3'

# ====================================
# Ruby Standard Library Compatibility
# ====================================

gem 'base64'
gem 'irb'
gem 'logger'
gem 'psych', '~> 5.2.3'
gem 'rdoc'
gem 'stringio', '~> 3.1.6'
gem 'reline'

# ====================================
# Third-Party Service Integrations
# ====================================

gem 'aws-sdk-sesv2', '~> 1.74', require: false
gem 'sendgrid-ruby', require: false
gem 'sentry-ruby', require: false
gem 'stackprof', require: false
gem 'stripe', require: false
gem 'syslog'

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
  gem 'rackup'
  gem 'rerun', '~> 0.14'

  # Code quality and language server
  gem 'rubocop', '~> 1.81.7', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-sequel', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'ruby-lsp', require: false
  gem 'syntax_tree', require: false
end

group :test do
  # Note: FakeRedis removed due to redis 5.x incompatibility
  # See spec_helper.rb for details about mock_redis as future alternative
  gem 'climate_control'
  gem 'ostruct'   # OpenStruct library for creating data objects (required by json)
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


# Optional alternate server - install with: bundle install --with optional
#
# Start with:
#   $ RUBY_YJIT_ENABLE=1 bundle exec puma -p 7143 -t 4:16 -w 2
#
# Arguments explained:
#   RUBY_YJIT_ENABLE=1  - Enable Ruby's JIT compiler for better performance
#   -p 7143             - Run on port 7143
#   -t 4:16             - Use min 4, max 16 threads per worker
#   -w 2                - Run 2 worker processes (clustered mode)
group :optional do
  gem 'puma', '~> 6.6'
end
