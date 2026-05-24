# spec/unit/onetime/application/error_resolver_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/application/error_resolver'

RSpec.describe Onetime::Application::ErrorResolver do
  # Capture the kwargs I18n.t is called with so each example can assert on
  # the locale / default / interpolation values independently of RSpec's
  # keyword-arg matcher quirks (the resolver passes them all via **).
  let(:captured_calls) { [] }

  def stub_i18n(return_value: 'translated', raise_error: nil)
    allow(I18n).to receive(:t) do |key, **opts|
      captured_calls << { key: key, opts: opts }
      raise raise_error if raise_error
      return_value
    end
  end

  let(:req) do
    instance_double(Rack::Request, env: { 'otto.locale' => 'fr_FR' })
  end

  describe '.resolve!' do
    context 'when error has an error_key' do
      let(:error) do
        Onetime::Forbidden.new('legacy fallback', error_key: 'api.errors.forbidden')
      end

      it 'replaces the message with the I18n-resolved string' do
        stub_i18n(return_value: 'Interdit')

        result = described_class.resolve!(error, req)

        expect(result).to be(error)
        expect(error.message).to eq('Interdit')
        # to_s must track the mutation too — loggers and middleware that call
        # error.to_s instead of error.message would otherwise see the original
        # constructor-time message via Exception's C-level slot. See the
        # to_s override on Onetime::Problem / Onetime::Forbidden.
        expect(error.to_s).to eq('Interdit')
        expect(captured_calls.first).to include(key: 'api.errors.forbidden')
        expect(captured_calls.first[:opts]).to include(
          locale: 'fr_FR',
          default: 'legacy fallback',
        )
      end
    end

    context 'when error has no error_key' do
      let(:error) { Onetime::Forbidden.new('untouched message') }

      it 'returns the error unchanged without calling I18n' do
        expect(I18n).not_to receive(:t)

        result = described_class.resolve!(error, req)

        expect(result).to be(error)
        expect(error.message).to eq('untouched message')
        expect(error.error_key).to be_nil
      end
    end

    context 'when I18n.t raises' do
      let(:error) do
        Onetime::Forbidden.new('', error_key: 'api.errors.broken')
      end

      it 'rescues the failure and falls back to error_key as the message' do
        stub_i18n(raise_error: I18n::InvalidLocale.new('xx'))
        allow(OT).to receive(:le)

        result = described_class.resolve!(error, req)

        expect(result).to be(error)
        expect(error.message).to eq('api.errors.broken')
        expect(OT).to have_received(:le).with(/\[ErrorResolver\] Failed to resolve api\.errors\.broken/)
      end

      it 'preserves an existing non-empty message when I18n.t fails' do
        # The rescue's fallback-to-error_key only fires when the pre-set
        # message is nil or empty — a non-empty legacy message must survive
        # the failed lookup so the client still sees a usable English string.
        error_with_message = Onetime::Forbidden.new(
          'existing English message',
          error_key: 'api.errors.broken',
        )
        stub_i18n(raise_error: StandardError.new('boom'))
        allow(OT).to receive(:le)

        described_class.resolve!(error_with_message, req)

        expect(error_with_message.message).to eq('existing English message')
        expect(OT).to have_received(:le).with(/\[ErrorResolver\] Failed to resolve api\.errors\.broken/)
      end
    end

    context 'when req is nil' do
      let(:error) do
        Onetime::Forbidden.new('fallback', error_key: 'api.errors.forbidden')
      end

      it 'uses I18n.default_locale instead of reading from the request' do
        allow(I18n).to receive(:default_locale).and_return(:en)
        stub_i18n(return_value: 'Forbidden')

        described_class.resolve!(error, nil)

        expect(error.message).to eq('Forbidden')
        expect(captured_calls.first[:opts]).to include(locale: :en)
      end
    end

    context 'when error carries args for interpolation' do
      let(:error) do
        Onetime::FormError.new(
          'fallback',
          error_key: 'api.errors.too_many',
          args: { max: 5, name: 'widgets' },
        )
      end

      it 'forwards args as keyword arguments to I18n.t' do
        stub_i18n(return_value: 'Trop de widgets (max 5)')

        described_class.resolve!(error, req)

        expect(error.message).to eq('Trop de widgets (max 5)')
        expect(captured_calls.first[:opts]).to include(
          locale: 'fr_FR',
          default: 'fallback',
          max: 5,
          name: 'widgets',
        )
      end
    end
  end
end
