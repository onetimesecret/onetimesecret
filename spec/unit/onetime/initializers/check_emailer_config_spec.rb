# spec/unit/onetime/initializers/check_emailer_config_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail'

# Boot check for the mail delivery configuration. It builds the backend once
# so a configuration it cannot be built from is logged on deploy, and it
# never raises: a broken mail setting stops mail, not boot.
RSpec.describe Onetime::Initializers::CheckEmailerConfig do
  subject(:initializer) { described_class.new }

  let(:logger) { instance_double('SemanticLogger::Logger', debug: nil, error: nil) }

  before do
    allow(OT).to receive(:boot_logger).and_return(logger)
  end

  it 'is optional' do
    expect(described_class.instance_variable_get(:@optional)).to be true
  end

  context 'when the backend can be built' do
    before do
      allow(Onetime::Mail::Mailer).to receive(:validate_delivery_config!).and_return('smtp')
    end

    it 'logs no error' do
      initializer.execute({})

      expect(logger).not_to have_received(:error)
      expect(logger).to have_received(:debug).with('Mail delivery configuration checked', provider: 'smtp')
    end
  end

  context 'when the configuration cannot build the backend' do
    before do
      allow(Onetime::Mail::Mailer).to receive(:validate_delivery_config!)
        .and_raise(Onetime::Mail::ConfigurationError.new('SMTP host must be configured', provider: 'smtp'))
    end

    it 'does not raise' do
      expect { initializer.execute({}) }.not_to raise_error
    end

    it 'logs a mail configuration error naming the provider' do
      initializer.execute({})

      expect(logger).to have_received(:error).with(
        'Mail configuration error, email cannot be sent',
        provider: 'smtp',
        error: 'SMTP host must be configured',
      )
    end
  end

  # Through the real mailer, with no SMTP host anywhere.
  context 'with mode smtp and no host' do
    before do
      allow(Onetime::Mail::Mailer).to receive(:emailer_config).and_return('mode' => 'smtp', 'host' => '')
      allow(Onetime::Mail::Mailer).to receive(:log_info)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('SMTP_HOST', nil).and_return(nil)
      Onetime::Mail::Mailer.reset!
    end

    after { Onetime::Mail::Mailer.reset! }

    it 'logs the missing host as a mail configuration error' do
      initializer.execute({})

      expect(logger).to have_received(:error).with(
        'Mail configuration error, email cannot be sent',
        provider: 'smtp',
        error: 'SMTP host must be configured',
      )
    end

    it 'leaves the mailer to build its own backend later' do
      initializer.execute({})

      expect(Onetime::Mail::Mailer.instance_variable_get(:@delivery_backend)).to be_nil
    end
  end
end
