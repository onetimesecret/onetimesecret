# spec/unit/onetime/models/custom_domain/brand_settings_global_defaults_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::CustomDomain::BrandSettingsConstants do
  # Read before boot (auth MFA config, TOTP issuer), when OT.conf is nil.
  it 'answers GLOBAL_DEFAULTS and the neutral color while OT.conf is nil' do
    allow(OT).to receive(:conf).and_return(nil)

    expect(described_class.global_defaults).to eq(described_class::GLOBAL_DEFAULTS)
    expect(described_class.defaults[:primary_color]).to eq(described_class::DEFAULTS[:primary_color])
  end
end
