# spec/support/helpers/emailer_config_helpers.rb
#
# frozen_string_literal: true

# Give the mailer an emailer section for one example.
#
# Onetime::Mail::Mailer, ProviderRegistry.detect_provider and the email config
# summary read emailer.* (and email_providers.*) through OT.conf.get, so a spec
# that wants a particular emailer config stubs OT.conf with it. The rest of the
# config is kept, so templates and other readers see the suite config.
module EmailerConfigHelpers
  # @param emailer [Hash] the emailer section, String keys
  # @param email_providers [Hash, nil] the email_providers section; nil keeps
  #   the suite's
  # @return [Hash] the stubbed config
  def stub_emailer_config(emailer, email_providers: nil)
    sections = { 'emailer' => emailer }
    sections['email_providers'] = email_providers unless email_providers.nil?
    conf = OT::Config.wrap(OT.conf.merge(sections))
    allow(OT).to receive(:conf).and_return(conf)
    conf
  end
end

RSpec.configure do |config|
  config.include EmailerConfigHelpers
end
