# Gemfile
# typed: false

#
# Recommended: Ruby 3.4+
#
# status: normal maintenance
# release date: 2024-12-25
# normal maintenance until: TBD
# end of life: 2028ish
#
# We support versions of Ruby that are still in normal maintenance.
#
ruby '>= 3.4'

source 'https://rubygems.org/'

# ====================================
# Core Application Framework
# ====================================

# Web framework and routing
gem 'otto', '~> 1.4.0'
gem 'roda', '~> 3.0'


# Web server and middleware
gem 'puma', '~> 6.6'
gem 'rack', '>= 3.1.16', '< 4.0'
gem 'rack-contrib', '~> 2.5.0'
gem 'rack-protection', '~> 4.1'
gem 'rack-session', '~> 2.1.1'
gem 'rackup'
gem 'rack-utf8_sanitizer'

# Authentication framework
gem 'rodauth', '~> 2.0'

# ====================================
# Database & DB Tools
# ====================================

# ORM and database drivers
gem 'familia', '~> 2.0.0.pre15'
gem 'pg', '~> 1.4'
gem 'sequel', '~> 5.0'
gem 'sqlite3', '~> 1.6'

# Redis/Valkey
gem 'redis', '~> 5.4.0'
gem 'uri-valkey', '~> 1.4.0'

# ====================================
# Security & Encryption
# ====================================

gem 'bcrypt', '~> 3.1'
gem 'encryptor', '= 1.1.3'
gem 'jwt', '~> 2.7'

# Advanced authentication
gem 'rotp', '~> 6.2'
gem 'rqrcode', '~> 2.2'
gem 'webauthn', '~> 3.0'

# ====================================
# Data Processing & Utilities
# ====================================

# JSON processing
gem 'json'
gem 'json_schemer'
gem 'oj', '~> 3.16'

# String and data processing
gem 'drydock', '~> 1.0.0'
gem 'fastimage', '~> 2.4'
gem 'mail', '~> 2.8'
gem 'mustache'
gem 'public_suffix'
gem 'tty-table', '~> 0.12'

# HTTP clients
gem 'http', '~> 5.1'
gem 'httparty'

# Email validation
gem 'truemail'

# ====================================
# Ruby Standard Library Compatibility
# ====================================

gem 'base64'
gem 'irb'
gem 'logger'                 # Used by Truemail
gem 'ostruct', '~> 0.6.2'    # Required by json
gem 'psych', '~> 5.2.3'
gem 'rdoc'
gem 'stringio', '~> 3.1.6'

# ====================================
# Third-Party Service Integrations
# ====================================

gem 'aws-sdk-sesv2', '~> 1.74'
gem 'sendgrid-ruby'
gem 'sentry-ruby', require: false
gem 'stripe', require: false

# ====================================
# Development & Testing Dependencies
# ====================================

group :development, :test do
  gem 'benchmark'
  gem 'database_cleaner-sequel', '~> 2.0'
  gem 'factory_bot', '~> 6.4'
  gem 'faker', '~> 3.2'
end

group :development do
  # Debugging tools
  gem 'debug', require: false
  gem 'rerun', '~> 0.14'

  # Development utilities
  gem 'rack-proxy', require: false
  gem 'stackprof', require: false

  # Code quality and language server
  gem 'rubocop', '~> 1.79', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'ruby-lsp', require: false
  gem 'solargraph', require: false
  gem 'syntax_tree', require: false
end

group :test do
  gem 'fakeredis', require: 'fakeredis/rspec'
  gem 'rack-test', require: false
  gem 'rspec', git: 'https://github.com/rspec/rspec'
  gem 'simplecov', require: false
  gem 'tryouts', '~> 3.6.0', require: false

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
