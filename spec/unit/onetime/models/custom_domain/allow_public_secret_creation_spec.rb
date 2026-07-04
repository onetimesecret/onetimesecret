# spec/unit/onetime/models/custom_domain/allow_public_secret_creation_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Decision table for CustomDomain#allow_public_secret_creation? — the
# authorization gate consumed by the anonymous secret-creation API
# (base_secret_action#validate_domain_permissions). It must authorize the
# public create form ONLY for an enabled homepage in a recognised create
# mode, and fail CLOSED in every other case: missing config, disabled,
# incoming mode, or a corrupt/unrecognised stored secrets_mode.
#
# The end-to-end path also has try-file coverage
# (try/unit/models/custom_domain_homepage_config_try.rb); this keeps the
# gate's decision table self-contained in the RSpec unit suite, exercising
# the real HomepageConfig predicates (enabled? / recognized_secrets_mode? /
# incoming_mode?) without touching Redis.
RSpec.describe Onetime::CustomDomain, '#allow_public_secret_creation?' do
  subject(:domain) do
    cd = described_class.new
    allow(cd).to receive(:identifier).and_return('domain123')
    cd
  end

  # Return a real HomepageConfig from the class finder so the gate runs the
  # genuine predicate logic rather than stubbed booleans.
  def stub_homepage_config(enabled:, secrets_mode:)
    config = Onetime::CustomDomain::HomepageConfig.new(
      domain_id: 'domain123', enabled: enabled, secrets_mode: secrets_mode
    )
    allow(Onetime::CustomDomain::HomepageConfig)
      .to receive(:find_by_domain_id).with('domain123').and_return(config)
  end

  context 'when the homepage config record is missing' do
    it 'fails closed rather than assuming a public create form' do
      allow(Onetime::CustomDomain::HomepageConfig)
        .to receive(:find_by_domain_id).with('domain123').and_return(nil)
      allow(OT).to receive(:le)

      expect(domain.allow_public_secret_creation?).to be(false)
    end
  end

  context 'when enabled in create mode' do
    it 'authorizes anonymous secret creation' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'create')
      expect(domain.allow_public_secret_creation?).to be(true)
    end
  end

  context 'when enabled with a blank (legacy/unset) secrets_mode' do
    it 'authorizes creation, reading blank as the historical create form' do
      stub_homepage_config(enabled: 'true', secrets_mode: '')
      expect(domain.allow_public_secret_creation?).to be(true)
    end
  end

  context 'when disabled' do
    it 'fails closed regardless of the stored mode' do
      stub_homepage_config(enabled: 'false', secrets_mode: 'create')
      expect(domain.allow_public_secret_creation?).to be(false)
    end
  end

  context 'when enabled in incoming mode' do
    it 'fails closed — visitors send secrets TO recipients, not create them' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'incoming')
      expect(domain.allow_public_secret_creation?).to be(false)
    end
  end

  context 'when the stored secrets_mode is corrupt/unrecognised' do
    it 'fails closed rather than falling open to the create form' do
      stub_homepage_config(enabled: 'true', secrets_mode: 'corrupted-mode')
      expect(domain.allow_public_secret_creation?).to be(false)
    end
  end
end
