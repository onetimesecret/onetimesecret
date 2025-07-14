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

gem 'truemail'
gem 'xdg'

gem 'addressable'
gem 'altcha', '~> 0.2.1'

gem 'rack', '>= 2.2.12', '< 3.0'
gem 'rack-contrib', '~> 2.5'
gem 'rack-protection', '~> 3.2'
gem 'rack-utf8_sanitizer', '~> 1.10.1'

gem 'dotenv'
gem 'json_schemer'
gem 'multi_json'
gem 'mustache'
gem 'public_suffix'
gem 'thin'

gem 'drydock'
gem 'familia', '~> 1.2.0'
gem 'gibbler'
gem 'otto', '~> 1.1.0.pre.alpha4'
gem 'storable'
gem 'uri-redis', '~> 1.3.0'

if ENV['RACK_ENV'] == 'development' && ENV['CI'].to_s.empty?
  gem 'rhales', path: '../rhales'
else
  gem 'rhales', '~> 0.4.0'
end

gem 'concurrent-ruby', '~> 1.3.5'
gem 'redis', '~> 5.4.0'

gem 'bcrypt'
gem 'encryptor', '= 1.1.3'

gem 'fastimage', '~> 2.4'
gem 'hashdiff'
gem 'httparty'
gem 'mail'
gem 'net-imap', '~> 0.5.7'

gem 'psych', '~> 5.2.3'
gem 'stringio', '~> 3.1.6'

# As of Ruby 3.4, these are no longer in the standard library
#
# These gems are included to suppress warnings about certain libraries
# no longer being part of the default gems starting from Ruby 3.5.0.
# Including them explicitly ensures they are part of the application's
# dependencies and silences the warnings.
gem 'base64'
gem 'syslog', '~> 0.3.0'

# As of Ruby 3.5, these are no longer in the standard library
gem 'fiddle'    # Fiddle library for handling dynamic libraries (required by reline)
gem 'irb'       # IRB
gem 'logger'    # Logger library for logging messages (required by truemail)
gem 'ostruct'   # OpenStruct library for creating data objects (required by json)
gem 'rdoc'      # IRB
gem 'reline'

# Third-party services
gem 'aws-sdk-sesv2', '~> 1.74'
gem 'sendgrid-ruby'
gem 'sentry-ruby', require: false
gem 'stripe', require: false

group :development, :test do
  gem 'benchmark'
end

group :development do
  gem 'byebug', require: false
  # Enable for Debug Adapter Protocol. Not included with the development group
  # group because it lags on byebug version.
  # gem 'byebug-dap', require: false
  gem 'pry', require: false
  gem 'pry-byebug', require: false
  gem 'rack-proxy', require: false
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'ruby-lsp', require: false
  gem 'stackprof', require: false
  gem 'syntax_tree', require: false
end

group :test do
  gem 'fakeredis', require: 'fakeredis/rspec'
  gem 'rack-test', require: false
  gem 'rspec', git: 'https://github.com/rspec/rspec'
  gem 'simplecov', require: false
  %w[rspec-core rspec-expectations rspec-mocks rspec-support].each do |lib|
    gem lib, git: 'https://github.com/rspec/rspec', glob: "#{lib}/#{lib}.gemspec"
  end
  gem 'tryouts', '~> 3.0.0', require: false
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
