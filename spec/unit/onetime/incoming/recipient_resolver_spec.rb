# spec/unit/onetime/incoming/recipient_resolver_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/incoming/recipient_resolver'

# Isolation tests for RecipientResolver#require_domain_entitlement!
#
# This spec focuses on the i18n error_key shape carried by the Forbidden
# raise when a custom domain has no resolvable owning organization. Broader
# behavior (canonical no-op, EntitlementRequired derivation) lives in the
# tryouts under try/features/incoming/. The HTTP edge resolver is covered
# by spec/unit/onetime/application/error_resolver_spec.rb.
#
RSpec.describe Onetime::Incoming::RecipientResolver do
  describe '#require_domain_entitlement!' do
    let(:resolver) do
      described_class.new(domain_strategy: :custom, display_domain: 'secrets.acme.com')
    end

    context 'when the custom domain has no resolvable owning organization' do
      before do
        # Stub the private custom_domain_record lookup so we don't need Redis
        # state. The record exists but its primary_organization is nil — same
        # Forbidden raise as the missing-record case (custom_domain_record
        # returns nil) since both arrive at owning_org.nil? on the next line.
        allow(resolver).to receive(:custom_domain_record).and_return(
          double('CustomDomain', primary_organization: nil),
        )
      end

      it 'raises Onetime::Forbidden' do
        expect { resolver.require_domain_entitlement!('incoming_secrets') }
          .to raise_error(Onetime::Forbidden)
      end

      it 'preserves the legacy English message as the fallback' do
        expect { resolver.require_domain_entitlement!('incoming_secrets') }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.message).to eq('Custom domain organization could not be resolved')
          end
      end

      it 'tags the error with the custom_domain_unresolved i18n key' do
        expect { resolver.require_domain_entitlement!('incoming_secrets') }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.error_key).to eq('api.incoming.errors.custom_domain_unresolved')
          end
      end

      it 'sets args to an empty hash (no interpolation values)' do
        expect { resolver.require_domain_entitlement!('incoming_secrets') }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.args).to eq({})
          end
      end

      it 'serializes error_key into to_h for the HTTP response body' do
        expect { resolver.require_domain_entitlement!('incoming_secrets') }
          .to raise_error(Onetime::Forbidden) do |error|
            expect(error.to_h).to include(
              error: 'Custom domain organization could not be resolved',
              error_type: 'Forbidden',
              error_key: 'api.incoming.errors.custom_domain_unresolved',
            )
          end
      end
    end

    context 'when the domain strategy is canonical (no-op path)' do
      let(:resolver) { described_class.new(domain_strategy: :canonical) }

      it 'returns true without raising (no domain to resolve)' do
        expect(resolver.require_domain_entitlement!('incoming_secrets')).to be true
      end
    end
  end
end
