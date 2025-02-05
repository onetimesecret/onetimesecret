# frozen_string_literal: true
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
ruby '>= 3.1.5'

source 'https://rubygems.org/'

gem 'truemail'

gem 'addressable'

gem 'rack', '>= 2.2', '< 3.0'
gem 'rack-contrib', '~> 2.5'

gem 'dotenv'
gem 'multi_json'
gem 'mustache'
gem 'public_suffix'
gem 'thin'

gem 'drydock'
#gem 'familia', path: '/Users/d/Projects/opensource/d/familia'
gem 'familia', '~> 1.1.0.pre.rc1'

gem 'gibbler'

gem 'otto', '~> 1.1.0.pre.alpha4'

gem 'redis', '~> 5.3.0'
gem 'storable'
gem 'sysinfo'
gem 'uri-redis', '~> 1.3.0'

gem 'bcrypt'
gem 'encryptor', '= 1.1.3'

gem 'httparty'
gem 'sendgrid-ruby'

gem 'mail'

gem "fastimage", "~> 2.3"

gem 'psych', '~> 5.2.2'
gem 'stringio', '~> 3.1.1'

# As of Ruby 3.4, these are no longer in the standard library
#
# These gems are included to suppress warnings about certain libraries
# no longer being part of the default gems starting from Ruby 3.5.0.
# Including them explicitly ensures they are part of the application's
# dependencies and silences the warnings.
gem 'base64'
gem 'syslog', '~> 0.2.0'

# As of Ruby 3.5, these are no longer in the standard library
gem 'fiddle'   # Fiddle library for handling dynamic libraries (required by reline)
gem 'logger'   # Logger library for logging messages (required by truemail)
gem 'ostruct'  # OpenStruct library for creating data objects (required by json)
gem 'rdoc'     # IRB

gem 'byebug', require: false, group: :development
gem 'byebug-dap', require: false, group: :development
gem 'pry', require: false, group: :development
gem 'pry-byebug', require: false, group: :development
gem 'rack-proxy', require: false, group: :development
gem 'rubocop', require: false, group: :development
gem 'rubocop-performance', require: false, group: :development
gem 'rubocop-thread_safety', require: false, group: :development
gem "sentry-ruby", require: false, group: :staging
gem 'sorbet', require: false, group: :development
gem 'sorbet-runtime', require: false, group: :development
gem 'spoom', require: false, group: :development
gem 'stackprof', require: false, group: :staging # bundle exec stackprof --text tmp/rubocop-stackprof.dump
gem 'stripe', require: false, group: :plans # bundle install --group plans
gem 'tapioca', require: false, group: :development
gem 'tryouts', require: false, group: :development

group :test do
  gem 'simplecov', require: false
  gem 'rspec', git: "https://github.com/rspec/rspec"
  %w[rspec-core rspec-expectations rspec-mocks rspec-support].each do |lib|
    gem lib, git: "https://github.com/rspec/rspec", glob: "#{lib}/#{lib}.gemspec"
  end
end
