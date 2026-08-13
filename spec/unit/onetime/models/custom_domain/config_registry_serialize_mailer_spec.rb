# spec/unit/onetime/models/custom_domain/config_registry_serialize_mailer_spec.rb
#
# frozen_string_literal: true

# ConfigRegistry.serialize('mailer', ...) — provider_verified tri-state.
#
# Regression: the colonel drift serializer coerced provider_verified with
# `.to_s == 'true'`, collapsing the tri-state into a boolean. Under the
# indeterminate-check contract, provider_verified can legitimately stay nil
# indefinitely (inconclusive checks preserve the prior value; a
# never-determined domain stays nil), and that coercion rendered "unknown"
# as false — indistinguishable from an authoritative provider negative.
#
# The serializer now uses MailerConfig#parse_boolean_field (nil-preserving),
# emitting true / false / nil. The admin field grid renders nil as "none".

require 'spec_helper'
require 'onetime/models/custom_domain/config_registry'
require 'onetime/models/custom_domain/mailer_config'

RSpec.describe Onetime::CustomDomain::ConfigRegistry do
  # Unsaved in-memory record: serialize only reads fields, never the datastore.
  def mailer_config(provider_verified:)
    config = Onetime::CustomDomain::MailerConfig.new(
      domain_id: 'domain-tristate',
      provider: 'smtp2go',
      from_name: 'Sender',
      from_address: 'notify@example.com',
    )
    config.provider_verified = provider_verified
    config
  end

  def serialized(provider_verified:)
    described_class.serialize('mailer', mailer_config(provider_verified: provider_verified))
  end

  describe "serialize('mailer') provider_verified tri-state" do
    it 'emits true when the provider confirmed verification (stored string)' do
      expect(serialized(provider_verified: 'true')[:provider_verified]).to be true
    end

    it 'emits false when the provider authoritatively said no (stored string)' do
      expect(serialized(provider_verified: 'false')[:provider_verified]).to be false
    end

    it 'emits nil when the outcome was never determined — unknown must not read as failed' do
      expect(serialized(provider_verified: nil)[:provider_verified]).to be_nil
    end

    it 'tolerates native boolean storage (legacy Familia deserialization)' do
      expect(serialized(provider_verified: true)[:provider_verified]).to be true
      expect(serialized(provider_verified: false)[:provider_verified]).to be false
    end
  end
end
