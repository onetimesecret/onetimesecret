# try/integration/auth/internal_request_debug_try.rb
#
# frozen_string_literal: true

# Debug: Understand why internal_request skips after_create_account
#
# Run:
#   source .env.test && AUTHENTICATION_MODE=full bundle exec try \
#     try/integration/auth/internal_request_debug_try.rb --agent

require_relative '../../../apps/web/auth/spec/spec_helper'

Tryouts.run do
  setup do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.boot!(:test, force: true)
    Onetime::Application::Registry.prepare_application_registry
  end

  tryout 'InternalRequest class structure' do
    drill 'Auth::Config exists', true do
      defined?(Auth::Config) == 'constant'
    end

    drill 'InternalRequest is a subclass of Auth::Config', true do
      internal_class = Auth::Config.const_get(:InternalRequest)
      internal_class < Auth::Config
    end

    drill 'Auth::Config has _after_create_account', true do
      Auth::Config.private_method_defined?(:_after_create_account)
    end

    drill 'InternalRequest has _after_create_account', true do
      internal_class = Auth::Config.const_get(:InternalRequest)
      internal_class.private_method_defined?(:_after_create_account)
    end

    drill 'Methods have same owner', :check do
      internal_class = Auth::Config.const_get(:InternalRequest)
      m1 = Auth::Config.instance_method(:_after_create_account)
      m2 = internal_class.instance_method(:_after_create_account)

      puts "\nAuth::Config._after_create_account owner: #{m1.owner}"
      puts "InternalRequest._after_create_account owner: #{m2.owner}"
      puts "Auth::Config._after_create_account source: #{m1.source_location}"
      puts "InternalRequest._after_create_account source: #{m2.source_location}"

      # Return comparison result
      m1.owner == m2.owner ? :same : :different
    end
  end
end
