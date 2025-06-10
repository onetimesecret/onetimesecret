# tests/unit/ruby/rspec/onetime/config/truemail_spec.rb

require_relative '../../spec_helper'

RSpec.xdescribe "Onetime mail validation (TrueMail) configuration" do
  describe "integration in Config.after_load" do
    let(:minimal_config) do
      {
        development: { enabled: false },
        site: {
          authentication: { enabled: true },
          host: 'example.com',
          secret: 'test_secret'
        },
        mail: {
          truemail: {
            default_validation_type: :regex,
            verifier_email: 'verify@example.com',
            allowed_domains_only: false,
            dns: ['1.1.1.1', '8.8.8.8']
          }
        }
      }
    end

    let(:full_truemail_config) do
      {
        default_validation_type: :regex,
        verifier_email: 'verify@example.com',
        verifier_domain: 'example.com',
        connection_timeout: 2,
        response_timeout: 2,
        connection_attempts: 3,
        allowed_domains_only: true,
        allowed_emails: ['allowed@example.com'],
        blocked_emails: ['blocked@example.com'],
        allowed_domains: ['gooddomain.com'],
        blocked_domains: ['baddomain.com'],
        blocked_mx_ip_addresses: ['10.0.0.1'],
        smtp_port: 25,
        smtp_fail_fast: false,
        smtp_safe_check: true,
        not_rfc_mx_lookup_flow: false,
        dns: ['1.1.1.1', '8.8.8.8'],
        logger: {
          tracking_event: :error,
          stdout: true
        }
      }
    end

    before do
      # Store original mail config
      @original_config = Onetime.instance_variable_get(:@conf)

      # Mock Truemail config
      @truemail_config = double('TruemailConfig')
      # Allow respond_to? calls with sensible defaults
      allow(@truemail_config).to receive(:respond_to?) do |method_name|
       # Only methods ending with = are considered valid setter methods
       method_name.to_s.end_with?('=') && method_name.to_s != 'invalid_key='
      end
      allow(Truemail).to receive(:configure).and_yield(@truemail_config)
    end

    after do
      # Restore original configuration
      Onetime.instance_variable_set(:@conf, @original_config)
    end

    it 'requires a configuration' do
      config = minimal_config.dup
      config[:mail].delete(:truemail)

      config_instance = Onetime::Config.new
      allow(config_instance).to receive(:unprocessed_config).and_return(config)

      expect { config_instance.send(:after_load) }
        .to raise_error(OT::Problem, /No TrueMail config found/)
    end

    it 'configures with minimal settings' do
      config = minimal_config.dup
      truemail_settings = config[:mail][:truemail]

      # Expectations for each setting in minimal config
      expect(@truemail_config).to receive(:default_validation_type=).with(truemail_settings[:default_validation_type])
      expect(@truemail_config).to receive(:verifier_email=).with(truemail_settings[:verifier_email])
      expect(@truemail_config).to receive(:whitelist_validation=).with(truemail_settings[:allowed_domains_only])
      expect(@truemail_config).to receive(:dns=).with(truemail_settings[:dns])

      config_instance = Onetime::Config.new
      allow(config_instance).to receive(:unprocessed_config).and_return(config)

      conf = config_instance.send(:after_load)
      Onetime.instance_variable_set(:@conf, conf)
      Onetime::Initializers::ConfigureTruemail.run
    end

    it 'logs error when Truemail config key does not exist' do
      test_config = minimal_config.dup
      test_config[:mail][:truemail][:invalid_key] = 'value'

      # Expect the error to be logged
      expect(Onetime).to receive(:le).with('config.invalid_key does not exist')

      # Set up stubs for valid keys present in minimal_config.
      # These are needed because configure_truemail iterates through all keys
      # and calls the corresponding setters.
      allow(@truemail_config).to receive(:default_validation_type=)
      allow(@truemail_config).to receive(:verifier_email=)
      # :allowed_domains_only maps to :whitelist_validation
      allow(@truemail_config).to receive(:whitelist_validation=)
      allow(@truemail_config).to receive(:dns=)

      # Allow the :invalid_key= setter to be called without error,
      # as configure_truemail attempts this call even after logging
      # (due to the commented-out 'next').
      allow(@truemail_config).to receive(:invalid_key=)

      config_instance = Onetime::Config.new
      allow(config_instance).to receive(:unprocessed_config).and_return(test_config)

      conf = config_instance.send(:after_load)
      OT.instance_variable_set(:@conf, conf)
      Onetime::Initializers::ConfigureTruemail.run
    end

    it 'maps custom key names to Truemail configuration keys' do
      test_config = minimal_config.dup
      test_config[:mail][:truemail] = {
        allowed_domains_only: true,
        allowed_emails: ['test@example.com'],
        blocked_domains: ['bad.com']
      }

      # Set expectations for the mapped keys
      expect(@truemail_config).to receive(:whitelist_validation=).with(true)
      expect(@truemail_config).to receive(:whitelisted_emails=).with(['test@example.com'])
      expect(@truemail_config).to receive(:blacklisted_domains=).with(['bad.com'])

      config_instance = Onetime::Config.new
      allow(config_instance).to receive(:unprocessed_config).and_return(test_config)

      conf = config_instance.send(:after_load)
      OT.instance_variable_set(:@conf, conf)
      Onetime::Initializers::ConfigureTruemail.run
    end

    it 'configures with all possible settings' do
      test_config = minimal_config.dup
      test_config[:mail][:truemail] = full_truemail_config

      # Set expectations for all keys
      expect(@truemail_config).to receive(:default_validation_type=).with(full_truemail_config[:default_validation_type])
      expect(@truemail_config).to receive(:verifier_email=).with(full_truemail_config[:verifier_email])
      expect(@truemail_config).to receive(:verifier_domain=).with(full_truemail_config[:verifier_domain])
      expect(@truemail_config).to receive(:connection_timeout=).with(full_truemail_config[:connection_timeout])
      expect(@truemail_config).to receive(:response_timeout=).with(full_truemail_config[:response_timeout])
      expect(@truemail_config).to receive(:connection_attempts=).with(full_truemail_config[:connection_attempts])
      expect(@truemail_config).to receive(:whitelist_validation=).with(full_truemail_config[:allowed_domains_only])
      expect(@truemail_config).to receive(:whitelisted_emails=).with(full_truemail_config[:allowed_emails])
      expect(@truemail_config).to receive(:blacklisted_emails=).with(full_truemail_config[:blocked_emails])
      expect(@truemail_config).to receive(:whitelisted_domains=).with(full_truemail_config[:allowed_domains])
      expect(@truemail_config).to receive(:blacklisted_domains=).with(full_truemail_config[:blocked_domains])
      expect(@truemail_config).to receive(:blacklisted_mx_ip_addresses=).with(full_truemail_config[:blocked_mx_ip_addresses])
      expect(@truemail_config).to receive(:smtp_port=).with(full_truemail_config[:smtp_port])
      expect(@truemail_config).to receive(:smtp_fail_fast=).with(full_truemail_config[:smtp_fail_fast])
      expect(@truemail_config).to receive(:smtp_safe_check=).with(full_truemail_config[:smtp_safe_check])
      expect(@truemail_config).to receive(:not_rfc_mx_lookup_flow=).with(full_truemail_config[:not_rfc_mx_lookup_flow])
      expect(@truemail_config).to receive(:dns=).with(full_truemail_config[:dns])
      expect(@truemail_config).to receive(:logger=).with(full_truemail_config[:logger])

      config_instance = Onetime::Config.new
      allow(config_instance).to receive(:unprocessed_config).and_return(test_config)

      conf = config_instance.send(:after_load)
      OT.instance_variable_set(:@conf, conf)
      Onetime::Initializers::ConfigureTruemail.run
    end

    context 'with key mapping tests' do
      it 'correctly maps all special keys' do
        # Define a config with all special keys that need mapping
        mapped_keys_config = {
          allowed_domains_only: true,
          allowed_emails: ['good@example.com'],
          blocked_emails: ['bad@example.com'],
          allowed_domains: ['gooddomain.com'],
          blocked_domains: ['baddomain.com'],
          blocked_mx_ip_addresses: ['10.0.0.1'],
          example_internal_key: 'test_value'
        }

        # Set up minimal config with these special keys
        test_config = minimal_config.dup
        test_config[:mail][:truemail] = mapped_keys_config

        # Set expectations for mapped keys
        expect(@truemail_config).to receive(:whitelist_validation=).with(true)
        expect(@truemail_config).to receive(:whitelisted_emails=).with(['good@example.com'])
        expect(@truemail_config).to receive(:blacklisted_emails=).with(['bad@example.com'])
        expect(@truemail_config).to receive(:whitelisted_domains=).with(['gooddomain.com'])
        expect(@truemail_config).to receive(:blacklisted_domains=).with(['baddomain.com'])
        expect(@truemail_config).to receive(:blacklisted_mx_ip_addresses=).with(['10.0.0.1'])
        expect(@truemail_config).to receive(:example_external_key=).with('test_value')

        config_instance = Onetime::Config.new
        allow(config_instance).to receive(:unprocessed_config).and_return(test_config)

        conf = config_instance.send(:after_load)
        OT.instance_variable_set(:@conf, conf)
        Onetime::Initializers::ConfigureTruemail.run
      end
    end
  end

  describe 'Onetime::Config::KEY_MAP' do
    it 'contains expected mapping keys' do
      expect(Onetime::Config::KEY_MAP).to include(
        allowed_domains_only: :whitelist_validation,
        allowed_emails: :whitelisted_emails,
        blocked_emails: :blacklisted_emails,
        allowed_domains: :whitelisted_domains,
        blocked_domains: :blacklisted_domains,
        blocked_mx_ip_addresses: :blacklisted_mx_ip_addresses,
        example_internal_key: :example_external_key,
      )
    end

    it 'is used by mapped_key method' do
      # Test a few key mappings to verify the method uses KEY_MAP correctly
      expect(Onetime::Config::Utils.mapped_key(:allowed_domains_only)).to eq(:whitelist_validation)
      expect(Onetime::Config::Utils.mapped_key(:example_internal_key)).to eq(:example_external_key)
      expect(Onetime::Config::Utils.mapped_key(:unmapped_key)).to eq(:unmapped_key)
    end
  end
end
