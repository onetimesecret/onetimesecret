# apps/web/billing/spec/cli/catalog_push_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'onetime/cli'
require_relative '../../cli/catalog_push_command'
require_relative '../../errors'

RSpec.describe 'Billing Catalog Push CLI', :billing_cli, :integration, :vcr do
  subject(:command) { Onetime::CLI::BillingCatalogPushCommand.new }

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  # Realistic plan definition matching actual billing.yaml structure
  let(:plan_def) do
    {
      'name' => 'Identity Plus',
      'tier' => 'plus',
      'tenancy' => 'shared',
      'region' => 'global',
      'display_order' => 2,
      'show_on_plans_page' => true,
      'entitlements' => %w[custom_branding api_access support_priority],
      'limits' => {
        'teams' => 3,
        'members_per_team' => 10,
        'custom_domains' => 2,
        'secret_lifetime' => 604_800,
        'secrets_per_day' => 100,
      },
      'prices' => [
        { 'amount' => 1999, 'currency' => 'USD', 'interval' => 'month' },
        { 'amount' => 19990, 'currency' => 'USD', 'interval' => 'year' },
      ],
    }
  end

  # Mock Stripe::Product with realistic structure
  def mock_product(overrides = {})
    defaults = {
      id: 'prod_test123',
      name: 'Identity Plus',
      marketing_features: [],
      metadata: {
        'app' => 'onetimesecret',
        'plan_id' => 'identity_plus_v1',
        'tier' => 'plus',
        'tenancy' => 'shared',
        'region' => 'GLOBAL',
        'display_order' => '2',
        'show_on_plans_page' => 'true',
        'entitlements' => 'custom_branding,api_access,support_priority',
        'limit_teams' => '3',
        'limit_members_per_team' => '10',
        'limit_custom_domains' => '2',
        'limit_secret_lifetime' => '604800',
        'limit_secrets_per_day' => '100',
        'currency' => 'cad',
        'ots_includes_plan' => '',
        'ots_is_popular' => 'false',
      },
    }
    double('Stripe::Product', defaults.merge(overrides))
  end

  # Mock Stripe::Price with realistic structure
  def mock_price(amount:, currency:, interval:, product_id: 'prod_test123')
    recurring = double('Recurring', interval: interval)
    double('Stripe::Price',
      id: "price_#{SecureRandom.hex(8)}",
      product: product_id,
      unit_amount: amount,
      currency: currency.downcase,
      recurring: recurring)
  end

  describe '#detect_product_updates (private)' do
    it 'returns empty hash when product matches plan definition exactly' do
      existing = mock_product
      result = command.send(:detect_product_updates, existing, plan_def)
      expect(result).to eq({})
    end

    it 'detects name changes' do
      existing = mock_product(name: 'Old Product Name')
      result = command.send(:detect_product_updates, existing, plan_def)

      expect(result).to have_key(:name)
      expect(result[:name][:from]).to eq('Old Product Name')
      expect(result[:name][:to]).to eq('Identity Plus')
    end

    it 'detects tier metadata changes' do
      metadata = mock_product.metadata.merge('tier' => 'basic')
      existing = mock_product(metadata: metadata)
      result = command.send(:detect_product_updates, existing, plan_def)

      expect(result).to have_key(:metadata_tier)
      expect(result[:metadata_tier][:from]).to eq('basic')
      expect(result[:metadata_tier][:to]).to eq('plus')
    end

    it 'detects limit field changes' do
      metadata = mock_product.metadata.merge('limit_teams' => '1')
      existing = mock_product(metadata: metadata)
      result = command.send(:detect_product_updates, existing, plan_def)

      expect(result).to have_key(:metadata_limit_teams)
      expect(result[:metadata_limit_teams][:from]).to eq('1')
      expect(result[:metadata_limit_teams][:to]).to eq('3')
    end

    it 'detects entitlements changes' do
      metadata = mock_product.metadata.merge('entitlements' => 'custom_branding')
      existing = mock_product(metadata: metadata)
      result = command.send(:detect_product_updates, existing, plan_def)

      expect(result).to have_key(:metadata_entitlements)
      expect(result[:metadata_entitlements][:from]).to eq('custom_branding')
      expect(result[:metadata_entitlements][:to]).to eq('custom_branding,api_access,support_priority')
    end

    it 'handles nil metadata values gracefully' do
      metadata = mock_product.metadata.merge('tier' => nil)
      existing = mock_product(metadata: metadata)

      # Should not raise, should detect the difference
      result = command.send(:detect_product_updates, existing, plan_def)
      expect(result).to have_key(:metadata_tier)
    end
  end

  describe '#analyze_price_changes (private)' do
    let(:existing_product) { mock_product }

    it 'returns empty array when no prices in plan definition' do
      plan_without_prices = plan_def.merge('prices' => [])
      result = command.send(:analyze_price_changes, 'identity_plus_v1', plan_without_prices, existing_product, [])
      expect(result).to eq([])
    end

    it 'returns prices with nil product_id when existing_product is nil (new product)' do
      result = command.send(:analyze_price_changes, 'identity_plus_v1', plan_def, nil, [])
      # For new products, we still analyze prices but set product_id to nil
      # The product_id will be resolved in apply_changes after product creation
      expect(result.length).to eq(2) # monthly and yearly prices
      expect(result.all? { |p| p[:product_id].nil? }).to be true
      expect(result.all? { |p| p[:plan_id] == 'identity_plus_v1' }).to be true
    end

    it 'skips incomplete price definitions missing amount' do
      incomplete_plan = plan_def.merge('prices' => [{ 'currency' => 'USD', 'interval' => 'month' }])
      result = command.send(:analyze_price_changes, 'identity_plus_v1', incomplete_plan, existing_product, [])
      expect(result).to eq([])
    end

    it 'inherits catalog currency when price omits currency' do
      no_currency_plan = plan_def.merge('prices' => [{ 'amount' => 1999, 'interval' => 'month' }])
      result = command.send(:analyze_price_changes, 'identity_plus_v1', no_currency_plan, existing_product, [], 'cad')
      expect(result.length).to eq(1)
      expect(result.first[:currency]).to eq('cad')
    end

    it 'skips incomplete price definitions missing interval' do
      incomplete_plan = plan_def.merge('prices' => [{ 'amount' => 1999, 'currency' => 'USD' }])
      result = command.send(:analyze_price_changes, 'identity_plus_v1', incomplete_plan, existing_product, [])
      expect(result).to eq([])
    end

    it 'returns empty when matching price already exists' do
      existing_prices = [mock_price(amount: 1999, currency: 'cad', interval: 'month')]
      single_price_plan = plan_def.merge('prices' => [{ 'amount' => 1999, 'currency' => 'USD', 'interval' => 'month' }])

      result = command.send(:analyze_price_changes, 'identity_plus_v1', single_price_plan, existing_product, existing_prices)
      expect(result).to eq([])
    end

    it 'returns new price when no match found' do
      existing_prices = [mock_price(amount: 999, currency: 'cad', interval: 'month')]
      single_price_plan = plan_def.merge('prices' => [{ 'amount' => 1999, 'currency' => 'USD', 'interval' => 'month' }])

      result = command.send(:analyze_price_changes, 'identity_plus_v1', single_price_plan, existing_product, existing_prices)

      expect(result.length).to eq(1)
      expect(result.first[:amount]).to eq(1999)
      expect(result.first[:currency]).to eq('cad')  # Resolved to lowercase
      expect(result.first[:interval]).to eq('month')
      expect(result.first[:plan_id]).to eq('identity_plus_v1')
    end

    it 'detects multiple missing prices' do
      # No existing prices, plan has monthly and yearly
      result = command.send(:analyze_price_changes, 'identity_plus_v1', plan_def, existing_product, [])

      expect(result.length).to eq(2)
      amounts = result.map { |p| p[:amount] }
      expect(amounts).to contain_exactly(1999, 19990)
    end
  end

  describe '#build_metadata (private)' do
    let(:app_identifier) { 'onetimesecret' }

    it 'includes required fields: app, plan_id, tier, tenancy, region' do
      result = command.send(:build_metadata, 'identity_plus_v1', plan_def, app_identifier)

      expect(result['app']).to eq('onetimesecret')
      expect(result['plan_id']).to eq('identity_plus_v1')
      expect(result['tier']).to eq('plus')
      expect(result['tenancy']).to eq('shared')
      expect(result['region']).to eq('GLOBAL')
    end

    it 'joins entitlements array with comma' do
      result = command.send(:build_metadata, 'identity_plus_v1', plan_def, app_identifier)
      expect(result['entitlements']).to eq('custom_branding,api_access,support_priority')
    end

    it 'includes display metadata' do
      result = command.send(:build_metadata, 'identity_plus_v1', plan_def, app_identifier)

      expect(result['display_order']).to eq('2')
      expect(result['show_on_plans_page']).to eq('true')
    end

    it 'includes limit fields when present' do
      result = command.send(:build_metadata, 'identity_plus_v1', plan_def, app_identifier)

      expect(result['limit_teams']).to eq('3')
      expect(result['limit_members_per_team']).to eq('10')
      expect(result['limit_custom_domains']).to eq('2')
      expect(result['limit_secret_lifetime']).to eq('604800')
      expect(result['limit_secrets_per_day']).to eq('100')
    end

    it 'omits limit fields when absent from plan definition' do
      plan_without_limits = plan_def.reject { |k, _| k == 'limits' }
      result = command.send(:build_metadata, 'identity_plus_v1', plan_without_limits, app_identifier)

      expect(result).not_to have_key('limit_teams')
      expect(result).not_to have_key('limit_members_per_team')
    end

    it 'handles empty entitlements array' do
      plan_no_entitlements = plan_def.merge('entitlements' => [])
      result = command.send(:build_metadata, 'identity_plus_v1', plan_no_entitlements, app_identifier)
      expect(result['entitlements']).to eq('')
    end

    it 'includes created timestamp' do
      result = command.send(:build_metadata, 'identity_plus_v1', plan_def, app_identifier)
      expect(result).to have_key('created')
      expect { Time.iso8601(result['created']) }.not_to raise_error
    end
  end

  describe '#analyze_changes (private)' do
    # Default match fields for most tests - single field matching by plan_id
    let(:match_fields) { ['plan_id'] }

    it 'identifies products to create when not in Stripe' do
      plans = { 'new_plan_v1' => plan_def }
      existing_products = {} # Empty - no products in Stripe
      existing_prices = {}

      result = command.send(:analyze_changes, plans, existing_products, existing_prices, false, match_fields)

      expect(result[:products_to_create].length).to eq(1)
      expect(result[:products_to_create].first[:plan_id]).to eq('new_plan_v1')
      expect(result[:products_to_update]).to be_empty
    end

    it 'identifies products to update when metadata differs' do
      plans = { 'identity_plus_v1' => plan_def }
      outdated_product = mock_product(name: 'Old Name')
      existing_products = { 'identity_plus_v1' => outdated_product }
      existing_prices = {}

      result = command.send(:analyze_changes, plans, existing_products, existing_prices, false, match_fields)

      expect(result[:products_to_create]).to be_empty
      expect(result[:products_to_update].length).to eq(1)
      expect(result[:products_to_update].first[:updates]).to have_key(:name)
    end

    it 'skips price analysis when skip_prices is true' do
      plans = { 'identity_plus_v1' => plan_def }
      existing_products = { 'identity_plus_v1' => mock_product }
      existing_prices = {} # No prices - would normally trigger creation

      result = command.send(:analyze_changes, plans, existing_products, existing_prices, true, match_fields)

      expect(result[:prices_to_create]).to be_empty
    end

    it 'identifies prices to create for existing products' do
      plans = { 'identity_plus_v1' => plan_def }
      existing_products = { 'identity_plus_v1' => mock_product }
      existing_prices = {} # No prices exist

      result = command.send(:analyze_changes, plans, existing_products, existing_prices, false, match_fields)

      expect(result[:prices_to_create].length).to eq(2) # monthly + yearly
    end

    it 'skips creation for legacy plans when product not found' do
      legacy_plan = plan_def.merge('legacy' => true, 'stripe_product_id' => 'prod_NotInRegion')
      plans = { 'identity' => legacy_plan }
      existing_products = {} # Product not found (e.g., filtered by region)
      existing_prices = {}

      result = capture_stdout do
        command.send(:analyze_changes, plans, existing_products, existing_prices, false, match_fields)
      end
      # Re-run to get the actual return value (capture_stdout consumes it)
      changes = command.send(:analyze_changes, plans, existing_products, existing_prices, false, match_fields)

      expect(changes[:products_to_create]).to be_empty
      expect(changes[:products_to_update]).to be_empty
      expect(changes[:prices_to_create]).to be_empty
    end

    it 'still updates legacy plans when product exists in Stripe' do
      legacy_plan = plan_def.merge('legacy' => true)
      outdated_product = mock_product(name: 'Old Legacy Name')
      plans = { 'identity' => legacy_plan }
      existing_products = { 'identity' => outdated_product }
      existing_prices = {}

      changes = command.send(:analyze_changes, plans, existing_products, existing_prices, false, match_fields)

      expect(changes[:products_to_create]).to be_empty
      expect(changes[:products_to_update].length).to eq(1)
      expect(changes[:products_to_update].first[:plan_id]).to eq('identity')
    end
  end

  describe '#call' do
    before do
      # Stub boot and Stripe configuration check
      allow(command).to receive(:boot_application!)
      allow(command).to receive(:stripe_configured?).and_return(true)
    end

    context 'with missing catalog file' do
      before do
        allow(Billing::Config).to receive(:config_exists?).and_return(false)
      end

      it 'reports catalog not found and exits early' do
        output = capture_stdout { command.call }
        expect(output).to include('Catalog not found')
      end
    end

    context 'with empty plans' do
      before do
        allow(Billing::Config).to receive(:config_exists?).and_return(true)
        allow(Billing::Config).to receive(:safe_load_config).and_return({ 'plans' => {} })
      end

      it 'reports no plans found' do
        output = capture_stdout { command.call }
        expect(output).to include('No plans found in catalog')
      end
    end

    context 'with --plan filter for unknown plan' do
      before do
        allow(Billing::Config).to receive(:config_exists?).and_return(true)
        allow(Billing::Config).to receive(:safe_load_config).and_return({
          'app_identifier' => 'onetimesecret',
          'plans' => { 'existing_plan' => plan_def },
        })
      end

      it 'shows error and lists available plans' do
        output = capture_stdout { command.call(plan: 'nonexistent_plan') }

        expect(output).to include("Plan 'nonexistent_plan' not found")
        expect(output).to include('Available plans: existing_plan')
      end
    end

    context 'when no changes needed' do
      before do
        allow(Billing::Config).to receive(:config_exists?).and_return(true)
        allow(Billing::Config).to receive(:safe_load_config).and_return({
          'app_identifier' => 'onetimesecret',
          'plans' => { 'identity_plus_v1' => plan_def },
        })
        allow(command).to receive(:fetch_existing_products).and_return({ 'identity_plus_v1' => mock_product })
        allow(command).to receive(:fetch_existing_prices).and_return({
          'identity_plus_v1' => [
            mock_price(amount: 1999, currency: 'cad', interval: 'month'),
            mock_price(amount: 19990, currency: 'cad', interval: 'year'),
          ],
        })
      end

      it 'reports Stripe is in sync' do
        output = capture_stdout { command.call }
        expect(output).to include('No changes needed - Stripe is in sync with catalog')
      end
    end

    context 'with legacy plan whose product is not in Stripe' do
      let(:legacy_plan) do
        plan_def.merge(
          'legacy' => true,
          'stripe_product_id' => 'prod_NotInThisRegion',
          'grandfathered_until' => '2028-01-31',
        )
      end

      before do
        allow(Billing::Config).to receive(:config_exists?).and_return(true)
        allow(Billing::Config).to receive(:safe_load_config).and_return({
          'app_identifier' => 'onetimesecret',
          'match_fields' => %w[plan_id region],
          'region' => 'UK',
          'plans' => { 'identity' => legacy_plan },
        })
        allow(command).to receive(:fetch_existing_products).and_return({})
        allow(command).to receive(:fetch_existing_prices).and_return({})
      end

      it 'reports no changes rather than creating a new product' do
        output = capture_stdout { command.call(dry_run: true) }

        expect(output).to include('skipping (legacy plan, product not found)')
        expect(output).to include('No changes needed')
        expect(output).not_to include('Products to CREATE')
      end
    end

    context 'with --dry-run flag' do
      before do
        allow(Billing::Config).to receive(:config_exists?).and_return(true)
        allow(Billing::Config).to receive(:safe_load_config).and_return({
          'app_identifier' => 'onetimesecret',
          'plans' => { 'new_plan_v1' => plan_def },
        })
        allow(command).to receive(:fetch_existing_products).and_return({})
        allow(command).to receive(:fetch_existing_prices).and_return({})
      end

      it 'shows changes with DRY RUN prefix' do
        output = capture_stdout { command.call(dry_run: true) }

        expect(output).to include('(DRY RUN)')
        expect(output).to include('[DRY RUN] Products to CREATE')
      end

      it 'does not call apply_changes' do
        expect(command).not_to receive(:apply_changes)
        capture_stdout { command.call(dry_run: true) }
      end
    end
  end
end
