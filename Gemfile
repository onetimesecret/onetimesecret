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
gem 'rack', '>= 2', '< 3.0'
gem 'rack-contrib'
gem 'rack-protection'
gem 'rack-utf8_sanitizer'

# ====================================
# Data Processing & Utilities
# ====================================

# JSON and data validation
gem 'json'
gem 'json_schemer'

# String and data processing
gem 'fastimage', '~> 2.4'
gem 'mail'
gem 'mustache'
gem 'public_suffix'

# HTTP client
gem 'httparty'

# Email validation
gem 'truemail'

# ====================================
# Database & Caching
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

if !ENV['LOCAL_DEV'].to_s.empty? && ENV['RACK_ENV'] == 'development' && ENV['CI'].to_s.empty?
  gem 'drydock', path: '../../d/drydock'
  gem 'familia', path: '../../d/familia'
  gem 'otto', path: '../../d/otto'
else
  gem 'drydock', '~> 1.0.0'
  gem 'familia', '~> 1.2.0'
  gem 'gibbler', '~> 1.0.0'
  gem 'otto', '~> 1.1.0.pre.alpha4'
end

# ====================================
# Ruby Standard Library Compatibility
# ====================================

# YAML and I/O
gem 'psych', '~> 5.2.3'
gem 'stringio', '~> 3.1.6'
gem 'tty-table', '~> 0.12'

# As of Ruby 3.4, these are no longer in the standard library
#
# These gems are included to suppress warnings about certain libraries
# no longer being part of the default gems starting from Ruby 3.5.0.
# Including them explicitly ensures they are part of the application's
# dependencies and silences the warnings.
gem 'base64'

# As of Ruby 3.5, these are no longer in the standard library
gem 'irb'                    # IRB
gem 'logger'                 # Logger library for logging messages (required by truemail)
gem 'ostruct', '~> 0.6.2'    # OpenStruct library for creating data objects (required by json)
gem 'rdoc'                   # IRB


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
  gem 'byebug', require: false
  gem 'pry', require: false
  gem 'pry-byebug', require: false

  # Development utilities
  gem 'rack-proxy', require: false
  gem 'stackprof', require: false

  # Code quality and language server
  gem 'rubocop', '~> 1.79', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'ruby-lsp', require: false
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
  gem 'tryouts', '~> 3.2.1', require: false

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
