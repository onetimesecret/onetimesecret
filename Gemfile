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

# Web server and middleware
gem 'puma', '~> 6.6'
gem 'rack', '>= 3.1.16', '< 4.0'
gem 'rack-contrib', '~> 2.5.0'
gem 'rack-protection', '~> 4.1'
gem 'rack-session', '~> 2.1.1'
gem 'rack-utf8_sanitizer'
gem 'rackup' # rubocop:disable Bundler/OrderedGems

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
gem 'tty-table', '~> 0.12'

# HTTP client
gem 'httparty'

# Email validation
gem 'truemail'

# ====================================
# Database & DB Tools
# ====================================

gem 'redis', '~> 5.4.0'
gem 'uri-valkey', '~> 1.4.0'

# ====================================
# Security & Encryption
# ====================================

gem 'bcrypt'
gem 'encryptor', '= 1.1.3'

# ====================================
# Internal Dependencies (local dev)
# ====================================

gem 'familia', '~> 2.0.0.pre15'
gem 'otto', '~> 1.4.0'

# ====================================
# Ruby Standard Library Compatibility
# ====================================

gem 'base64'
gem 'irb'
gem 'logger'                 # Used by Truemail
gem 'ostruct', '~> 0.6.2'
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
end

group :development do
  # Debugging tools
  gem 'debug', require: false

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
  # Enable for Debug Adapter Protocol. Not included with the
  # development group because it lags on byebug version.
  # gem 'byebug-dap', require: false
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
