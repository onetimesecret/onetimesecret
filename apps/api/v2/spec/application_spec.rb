# apps/api/v2/spec/application_spec.rb
#
# frozen_string_literal: true

require_relative '../../../spec_helper'
require 'v2/application'

# Test that the v2 rack app includes JSONBodyParser middleware
RSpec.describe V2::Application do
  describe 'middleware stack' do
    it 'includes JSONBodyParser middleware' do
      # The middleware is declared at class level with `use Rack::JSONBodyParser`
      # We can verify it's in the middleware stack by checking the class configuration
      middleware_classes = described_class.middleware.map do |middleware_spec|
        middleware_spec.first # First element is the middleware class
      end

      expect(middleware_classes).to include(Rack::JSONBodyParser)
    end

    it 'includes CsrfResponseHeader middleware' do
      middleware_classes = described_class.middleware.map do |middleware_spec|
        middleware_spec.first
      end

      expect(middleware_classes).to include(Onetime::Middleware::CsrfResponseHeader)
    end
  end
end
