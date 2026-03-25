# spec/integration/api/v1/auth_status_header_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Integration tests for V1 API X-OTS-Intended-Status header
#
# The V1 API historically returns 404 for all errors (breaking HTTP semantics).
# For backward compatibility, this is preserved, but clients can now use the
# X-OTS-Intended-Status header to determine the correct status code:
#
# - not_authorized_error: 404 status with X-OTS-Intended-Status: 401
# - error_response: 404 status with X-OTS-Intended-Status: 400
# - Successful requests: 200 status with no X-OTS-Intended-Status header
#
# Testing approach:
# We test the V1::ControllerBase methods directly by creating a minimal
# test harness that simulates the controller context.
#
RSpec.describe 'V1 API X-OTS-Intended-Status Header', type: :integration do
  before(:all) do
    require 'onetime'
    OT.boot! :test
    require_relative '../../../../apps/api/v1/controllers/base'
  end

  # Test class that includes V1::ControllerBase to test error methods
  let(:test_controller) do
    Class.new do
      include V1::ControllerBase

      attr_accessor :response_status, :response_headers, :response_body

      def initialize
        @response_status = nil
        @response_headers = {}
        @response_body = nil
      end

      # Minimal mock of res object
      def res
        @res ||= begin
          controller = self
          Class.new do
            define_method(:status=) { |s| controller.response_status = s }
            define_method(:[]=) { |k, v| controller.response_headers[k] = v }
          end.new
        end
      end

      # Mock json method
      def json(hsh)
        @response_body = hsh
      end
    end.new
  end

  describe '#not_authorized_error' do
    it 'sets HTTP status to 404 for backward compatibility' do
      test_controller.not_authorized_error

      expect(test_controller.response_status).to eq(404)
    end

    it 'sets X-OTS-Intended-Status header to 401' do
      test_controller.not_authorized_error

      expect(test_controller.response_headers['X-OTS-Intended-Status']).to eq('401')
    end

    it 'includes "Not authorized" in response body message' do
      test_controller.not_authorized_error

      expect(test_controller.response_body[:message]).to eq('Not authorized')
    end
  end

  describe '#error_response' do
    it 'sets HTTP status to 404 for backward compatibility' do
      test_controller.error_response('Test error message')

      expect(test_controller.response_status).to eq(404)
    end

    it 'sets X-OTS-Intended-Status header to 400' do
      test_controller.error_response('Test error message')

      expect(test_controller.response_headers['X-OTS-Intended-Status']).to eq('400')
    end

    it 'includes the error message in response body' do
      test_controller.error_response('Custom error text')

      expect(test_controller.response_body[:message]).to eq('Custom error text')
    end

    it 'merges additional hash data into response' do
      test_controller.error_response('Error', extra_field: 'value')

      expect(test_controller.response_body[:extra_field]).to eq('value')
    end
  end

  describe '#not_found_response' do
    it 'does NOT include X-OTS-Intended-Status header (404 is correct)' do
      test_controller.not_found_response('Resource not found')

      expect(test_controller.response_headers['X-OTS-Intended-Status']).to be_nil
    end

    it 'sets HTTP status to 404' do
      test_controller.not_found_response('Resource not found')

      expect(test_controller.response_status).to eq(404)
    end
  end
end
