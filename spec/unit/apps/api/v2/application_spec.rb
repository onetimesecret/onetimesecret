# tests/unit/ruby/rspec/apps/api/v2/application_spec.rb

require_relative '../../../../spec_helper'
require 'v2/application'

# Attempt to test that the v2 rack app includes JSONBodyParser middleware
RSpec.xdescribe V2::Application do
  describe 'middleware stack' do
    # Create mock middleware classes that might not be loaded in test env
    before(:all) do
      unless defined?(Rack::JSONBodyParser)
        module Rack
          class JSONBodyParser; end
        end
      end
    end

    it 'includes JSONBodyParser middleware' do
      # Mock the build_router method to avoid external dependencies
      allow_any_instance_of(described_class).to receive(:build_router).and_return(double('router').as_null_object)

      # Set up minimal environment for application initialization
      ENV['ONETIME_HOME'] ||= File.expand_path('../../../../../../../', __FILE__)

      # Verify JSONBodyParser is included in the middleware stack
      expect(Rack::Builder).to receive(:new) do |&block|
        builder = double('builder')
        allow(builder).to receive(:use)
        allow(builder).to receive(:run)
        allow(builder).to receive(:to_app).and_return(double('app'))
        allow(builder).to receive(:warmup).and_yield  # Add support for warmup

        # Critical expectation: verify JSONBodyParser is used
        expect(builder).to receive(:use).with(Rack::JSONBodyParser)

        # Allow the block to execute with our mock builder
        block.call(builder)
        builder
      end

      # Create application which triggers the middleware setup
      described_class.new
    end
  end
end
