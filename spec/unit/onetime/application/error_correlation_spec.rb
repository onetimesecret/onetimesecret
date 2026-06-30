# spec/unit/onetime/application/error_correlation_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/application/error_correlation'

# Namespaced dummy so short_class_name's namespace-stripping is exercised
# without coupling this spec to Onetime's error classes — the module under test
# is deliberately dependency-free, and this spec stays that way too. Defined at
# file scope (not inside the describe block) so the `class` keyword is legal.
module ErrorCorrelationSpecErrors
  class WidgetError < StandardError; end
end

RSpec.describe Onetime::Application::ErrorCorrelation do
  let(:request_id) { 'req-abc-123' }
  let(:widget)     { ErrorCorrelationSpecErrors::WidgetError.new('boom') }

  # An env carrying a request id, keyed exactly as Rack::RequestId sets it.
  def env_with_request_id
    { described_class::ENV_REQUEST_ID => request_id }
  end

  describe '.apply' do
    it 'echoes the request_id into the body without mutating the original' do
      body = { error_type: 'RecordNotFound' }
      out  = described_class.apply(body, env_with_request_id)

      expect(out[:request_id]).to eq(request_id)
      expect(body).not_to have_key(:request_id) # merge returned a copy
    end

    it 'stashes the error_type into env under ENV_ERROR_TYPE' do
      env = env_with_request_id
      described_class.apply({ error_type: 'RecordNotFound' }, env)

      expect(env[described_class::ENV_ERROR_TYPE]).to eq('RecordNotFound')
    end

    it 'omits request_id from the body when env carries none, but still stashes type' do
      env = {}
      out = described_class.apply({ error_type: 'RecordNotFound' }, env)

      expect(out).not_to have_key(:request_id)
      expect(env[described_class::ENV_ERROR_TYPE]).to eq('RecordNotFound')
    end

    it 'is nil-safe and returns the same body object when env is nil' do
      body = { error_type: 'Forbidden' }
      out  = nil

      expect { out = described_class.apply(body, nil, widget) }.not_to raise_error
      expect(out).to equal(body)
    end

    # to_h compaction can drop a nil error_type; the request log should still
    # name the failure via the exception class (with its namespace stripped).
    it 'falls back to the exception class name when the body omits error_type' do
      env = env_with_request_id
      out = described_class.apply({ error: 'oops' }, env, widget)

      expect(out).not_to have_key(:error_type)                         # body unchanged
      expect(env[described_class::ENV_ERROR_TYPE]).to eq('WidgetError') # log named it
      expect(out[:request_id]).to eq(request_id)
    end

    it "prefers the body's own error_type over the class-name fallback" do
      env = env_with_request_id
      described_class.apply({ error_type: 'email_mismatch' }, env, widget)

      expect(env[described_class::ENV_ERROR_TYPE]).to eq('email_mismatch')
    end

    it 'stashes nothing when there is neither a body error_type nor an exception' do
      env = env_with_request_id
      out = described_class.apply({ error: 'bare' }, env)

      expect(env).not_to have_key(described_class::ENV_ERROR_TYPE)
      expect(out[:request_id]).to eq(request_id) # request_id is still echoed
    end
  end

  describe '.short_class_name' do
    it 'strips the namespace from a nested class' do
      expect(described_class.short_class_name(widget)).to eq('WidgetError')
    end
  end

  # These keys are a cross-module contract: this module is the only production
  # writer, RequestLogger the only reader. Pin them so a rename can't silently
  # break correlation.
  describe 'env-key constants' do
    it 'pins ENV_ERROR_TYPE to the key RequestLogger reads' do
      expect(described_class::ENV_ERROR_TYPE).to eq('otto.error_type')
    end

    it 'pins ENV_REQUEST_ID to the Rack::RequestId env key' do
      expect(described_class::ENV_REQUEST_ID).to eq('HTTP_X_REQUEST_ID')
    end
  end
end
