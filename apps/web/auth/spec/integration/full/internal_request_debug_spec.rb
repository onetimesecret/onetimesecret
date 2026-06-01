# apps/web/auth/spec/integration/full/internal_request_debug_spec.rb
#
# frozen_string_literal: true

# Debug: Understand why internal_request skips after_create_account

require_relative '../../spec_helper'

RSpec.describe 'Debug: InternalRequest class structure', type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.boot!(:test, force: true)
    Onetime::Application::Registry.prepare_application_registry
  end

  it 'shows inheritance chain and method ownership' do
    puts "\n=== Auth::Config ==="
    puts "Auth::Config: #{Auth::Config}"
    puts "Auth::Config ancestors (first 5): #{Auth::Config.ancestors.first(5)}"

    internal_class = Auth::Config.const_get(:InternalRequest)
    puts "\n=== InternalRequest ==="
    puts "InternalRequest class: #{internal_class}"
    puts "InternalRequest ancestors (first 8): #{internal_class.ancestors.first(8)}"
    puts "InternalRequest < Auth::Config: #{internal_class < Auth::Config}"

    puts "\n=== _after_create_account method ==="
    puts "Auth::Config has _after_create_account: #{Auth::Config.private_method_defined?(:_after_create_account)}"
    puts "InternalRequest has _after_create_account: #{internal_class.private_method_defined?(:_after_create_account)}"

    if Auth::Config.private_method_defined?(:_after_create_account)
      m = Auth::Config.instance_method(:_after_create_account)
      puts "\nAuth::Config._after_create_account owner: #{m.owner}"
      puts "Auth::Config._after_create_account source_location: #{m.source_location}"
    end

    if internal_class.private_method_defined?(:_after_create_account)
      m = internal_class.instance_method(:_after_create_account)
      puts "\nInternalRequest._after_create_account owner: #{m.owner}"
      puts "InternalRequest._after_create_account source_location: #{m.source_location}"
    end

    # Check if they're the SAME method or different
    if Auth::Config.private_method_defined?(:_after_create_account) &&
       internal_class.private_method_defined?(:_after_create_account)
      m1 = Auth::Config.instance_method(:_after_create_account)
      m2 = internal_class.instance_method(:_after_create_account)
      puts "\n=== Method comparison ==="
      puts "Same owner? #{m1.owner == m2.owner}"
      puts "Same source? #{m1.source_location == m2.source_location}"

      # The key insight: If InternalRequest inherits the hook, it should work
      # If InternalRequest has a DIFFERENT method, that's the bug
      if m1.owner != m2.owner
        puts "\n*** BUG FOUND: InternalRequest has a different _after_create_account ***"
        puts "The internal class got its own version, not the one with your hook!"
      end
    end

    expect(true).to be true
  end

  it 'traces what after_create_account actually does' do
    internal_class = Auth::Config.const_get(:InternalRequest)

    # Create a mock scope/request to instantiate rodauth
    env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/',
      'SCRIPT_NAME' => '',
      'HTTP_HOST' => 'example.com',
      'rack.input' => StringIO.new(''),
      'rack.url_scheme' => 'https'
    }

    # Check the actual method chain for after_create_account
    puts "\n=== Method chain for after_create_account ==="

    # The public after_create_account calls: super, _after_create_account, hook_action
    puts "Auth::Config has after_create_account: #{Auth::Config.private_method_defined?(:after_create_account)}"
    puts "InternalRequest has after_create_account: #{internal_class.private_method_defined?(:after_create_account)}"

    if Auth::Config.private_method_defined?(:after_create_account)
      m = Auth::Config.instance_method(:after_create_account)
      puts "Auth::Config.after_create_account owner: #{m.owner}"
    end

    if internal_class.private_method_defined?(:after_create_account)
      m = internal_class.instance_method(:after_create_account)
      puts "InternalRequest.after_create_account owner: #{m.owner}"
    end

    expect(true).to be true
  end
end
