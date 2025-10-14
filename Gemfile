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

gem 'otto', '~> 2.0.0.pre2'
gem 'roda', '~> 3.0'
gem 'rodauth', '~> 2.0'

# Web server and middleware
gem 'puma', '~> 6.6'
gem 'rack', '>= 3.1.16', '< 4.0'
gem 'rack-contrib', '~> 2.5.0'
gem 'rack-protection', '~> 4.1'
gem 'rack-session', '~> 2.1.1'
gem 'rackup'
gem 'rack-utf8_sanitizer'

# ====================================
# Data Processing & Utilities
# ====================================

# JSON and data validation
gem 'json_schemer'

# String and data processing
gem 'drydock', '~> 1.0.0'
gem 'fastimage', '~> 2.4'
gem 'mail'
gem 'mustache'
gem 'public_suffix'
gem 'tilt'
gem 'tty-table', '~> 0.12'

# HTTP client
gem 'httparty'

# Email validation
gem 'truemail'

# ====================================
# Database & DB Tools
# ====================================

# ORMs and database drivers
gem 'familia', '~> 2.0.0.pre19'
gem 'sequel', '~> 5.0'

case ENV.fetch('DATABASE_ADAPTER', 'sqlite3').downcase
when 'postgresql', 'pg', 'postgres'
  gem 'pg', '~> 1.4'
else
  gem 'sqlite3', '~> 1.6'
end

# Redis/Valkey
gem 'redis', '~> 5.4.0'
gem 'uri-valkey', '~> 1.4.0'

# ====================================
# Security & Encryption
# ====================================

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
gem 'stringio', '~> 3.1.6'

# ====================================
# Third-Party Service Integrations
# ====================================

gem 'aws-sdk-sesv2', '~> 1.74', require: false
gem 'sendgrid-ruby', require: false
gem 'sentry-ruby', require: false
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
  gem 'rerun', '~> 0.14'

  # Development utilities
  gem 'rack-proxy', require: false
  gem 'stackprof', require: false

  # Code quality and language server
  gem 'rubocop', '~> 1.81.1', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'ruby-lsp', require: false
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
