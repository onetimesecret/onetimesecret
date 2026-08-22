# apps/web/core/spec/controllers/base_capture_error_spec.rb
#
# frozen_string_literal: true

# Tests for Core::Controllers::Base#capture_error scope ordering.
#
# The pseudonymous user ref must be applied AFTER the caller's block runs on
# the scope, so a block calling scope.set_user cannot replace the opaque ref
# with raw identifiers (email, custid). The block is intentionally NOT
# forwarded into Sentry.capture_exception for the same reason: Sentry runs a
# capture block against the event scope after with_scope's mutations.
#
# Run: pnpm run test:rspec apps/web/core/spec/controllers/base_capture_error_spec.rb

require 'spec_helper'
require 'sentry-ruby'

require_relative '../../controllers/base'

RSpec.describe Core::Controllers::Base do
  subject(:controller) { klass.new(req, res) }

  let(:klass) do
    Class.new do
      include Core::Controllers::Base
    end
  end

  let(:env) { { 'REQUEST_METHOD' => 'GET' } }
  let(:req) do
    request = double('Request')
    allow(request).to receive(:env).and_return(env)
    allow(request).to receive(:locale).and_return('en')
    request
  end
  let(:res) { double('Response') }

  let(:ex) { StandardError.new('boom') }

  let(:mock_scope) { double('Sentry::Scope') }

  let(:logger) do
    double('HttpLogger').tap do |log|
      allow(log).to receive(:debug)
      allow(log).to receive(:error)
    end
  end

  before do
    allow(OT).to receive(:d9s_enabled).and_return(true)
    allow(controller).to receive(:http_logger).and_return(logger)
    allow(controller).to receive(:cust).and_return(nil)

    allow(Sentry).to receive(:initialized?).and_return(true)
    allow(Sentry).to receive(:with_scope).and_yield(mock_scope)
    allow(Sentry).to receive(:capture_exception)
  end

  it 'runs the caller block on the scope before setting the pseudonymous user' do
    calls = []
    allow(Onetime::ErrorHandler).to receive(:set_diagnostics_user) { calls << :diagnostics_user }

    controller.send(:capture_error, ex) { |_scope| calls << :caller_block }

    expect(calls).to eq([:caller_block, :diagnostics_user])
  end

  it 'does not forward the caller block into capture_exception' do
    forwarded = :unset
    allow(Sentry).to receive(:capture_exception) { |*_args, &blk| forwarded = blk }

    controller.send(:capture_error, ex) { |_scope| nil }

    expect(forwarded).to be_nil
  end

  it 'lets the opaque ref win over a block that sets a raw user' do
    users = []
    allow(mock_scope).to receive(:set_user) { |user| users << user }
    allow(Onetime::ErrorHandler).to receive(:set_diagnostics_user) do |scope, _candidate|
      scope.set_user({ 'id' => 'opaque-ref' })
      true
    end

    controller.send(:capture_error, ex) do |scope|
      scope.set_user({ 'email' => 'raw@example.com' })
    end

    expect(users.last).to eq({ 'id' => 'opaque-ref' })
  end

  it 'still captures when no block is given' do
    allow(Onetime::ErrorHandler).to receive(:set_diagnostics_user).and_return(false)

    controller.send(:capture_error, ex)

    expect(Sentry).to have_received(:capture_exception).with(ex, level: :error)
  end
end
