# spec/integration/api/domains/homepage_secrets_entitlement_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Integration tests for homepage settings separation from brand settings.
#
# Homepage settings are managed via HomepageConfig (separate from brand
# settings). The UpdateDomainBrand endpoint no longer accepts
# allow_public_homepage — it strips the field from input.
#
RSpec.describe 'UpdateDomainBrand homepage field handling', type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test

    require 'domains/logic/domains/update_domain_brand'
  end

  # Build a logic instance just enough to call process_params.
  def create_brand_logic(params:)
    customer = double('Customer')
    allow(customer).to receive(:anonymous?).and_return(false)

    session = double('Session')
    allow(session).to receive(:[]) { |_key| nil }
    allow(session).to receive(:[]=)

    strategy_result = double('StrategyResult')
    allow(strategy_result).to receive(:session).and_return(session)
    allow(strategy_result).to receive(:user).and_return(customer)
    allow(strategy_result).to receive(:metadata).and_return({})

    DomainsAPI::Logic::Domains::UpdateDomainBrand.new(strategy_result, params)
  end

  describe 'strips allow_public_homepage from input' do
    it 'removes allow_public_homepage from brand_settings during process_params' do
      logic = create_brand_logic(
        params: { 'extid' => 'abc123', 'brand' => { 'allow_public_homepage' => 'true', 'primary_color' => '#FF0000' } },
      )
      logic.process_params

      expect(logic.brand_settings).not_to have_key('allow_public_homepage')
      expect(logic.brand_settings).to have_key('primary_color')
      expect(logic.brand_settings['primary_color']).to eq('#FF0000')
    end

    it 'results in empty brand_settings when only allow_public_homepage is provided' do
      logic = create_brand_logic(
        params: { 'extid' => 'abc123', 'brand' => { 'allow_public_homepage' => 'true' } },
      )
      logic.process_params

      expect(logic.brand_settings).to be_empty
    end

    it 'also removes allow_public_api from brand_settings' do
      logic = create_brand_logic(
        params: { 'extid' => 'abc123', 'brand' => { 'allow_public_api' => 'true', 'primary_color' => '#FF0000' } },
      )
      logic.process_params

      expect(logic.brand_settings).not_to have_key('allow_public_api')
      expect(logic.brand_settings).to have_key('primary_color')
    end

    it 'still accepts other brand fields normally' do
      logic = create_brand_logic(
        params: {
          'extid' => 'abc123',
          'brand' => {
            'allow_public_homepage' => 'true',
            'allow_public_api' => 'true',
            'font_family' => 'serif',
            'corner_style' => 'pill',
            'primary_color' => '#AABBCC',
          },
        },
      )
      logic.process_params

      expect(logic.brand_settings.keys).to contain_exactly('font_family', 'corner_style', 'primary_color')
    end
  end
end
