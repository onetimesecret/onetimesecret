# spec/unit/onetime/initializers/configure_domains_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# The features.domains.serve_unverified warning is logged at boot, by
# ConfigureDomains, once per process. Serving a request does not log it
# (spec/unit/onetime/middleware/domain_strategy_unverified_gate_spec.rb).
RSpec.describe Onetime::Initializers::ConfigureDomains do
  subject(:initializer) { described_class.new }

  # Model code logs through the 'App' category too, so this accepts every
  # message and the examples check only the serve_unverified warning.
  let(:app_logger) { instance_double(SemanticLogger::Logger).as_null_object }

  # @param domains [Hash] the features.domains section
  def configure(domains)
    conf             = YAML.load(YAML.dump(OT.conf))
    conf['features'] = (conf['features'] || {}).merge('domains' => domains)
    allow(OT).to receive(:conf).and_return(conf)
  end

  let(:warnings) { [] }

  def warned_count
    warnings.count('custom_domain.serve_unverified_enabled')
  end

  before do
    Onetime::CustomDomain.reset_serving_policy!
    allow(Onetime).to receive(:get_logger).and_call_original
    allow(Onetime).to receive(:get_logger).with('App').and_return(app_logger)
    allow(app_logger).to receive(:warn) { |message, *| warnings << message }
    allow(initializer).to receive(:app_logger).and_return(app_logger)

    # Boot state this initializer also sets; none of it is under test here.
    allow(Onetime::Runtime).to receive(:update_features)
    allow(Onetime::DomainValidation::Features).to receive_messages(
      load_from_config: nil, configured_settings: {}, api_configured?: true, strategy_name: 'approximated',
    )
    allow(initializer).to receive(:warn_if_default_shadows_custom_domain)
    allow(initializer).to receive(:warn_if_link_pool_shadows_custom_domains)
  end

  after { Onetime::CustomDomain.reset_serving_policy! }

  describe 'features.domains.serve_unverified' do
    it 'logs one warning at boot when true' do
      configure('enabled' => true, 'validation_strategy' => 'approximated', 'serve_unverified' => true)

      initializer.execute({})

      expect(app_logger).to have_received(:warn)
        .with('custom_domain.serve_unverified_enabled', hash_including(setting: 'features.domains.serve_unverified'))
        .once
    end

    it 'logs it once per process, however often boot runs' do
      configure('enabled' => true, 'validation_strategy' => 'approximated', 'serve_unverified' => true)

      3.times do
        boot = described_class.new
        allow(boot).to receive(:warn_if_default_shadows_custom_domain)
        allow(boot).to receive(:warn_if_link_pool_shadows_custom_domains)
        boot.execute({})
      end

      expect(warned_count).to eq(1)
    end

    [false, nil, 'true'].each do |value|
      it "logs nothing for #{value.inspect}" do
        configure('enabled' => true, 'validation_strategy' => 'approximated', 'serve_unverified' => value)

        initializer.execute({})

        expect(warned_count).to eq(0)
      end
    end

    it 'logs nothing while the domains feature is off' do
      configure('enabled' => false, 'validation_strategy' => 'approximated', 'serve_unverified' => true)

      initializer.execute({})

      expect(warned_count).to eq(0)
    end
  end
end
