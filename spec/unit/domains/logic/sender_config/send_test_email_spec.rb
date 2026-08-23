# spec/unit/domains/logic/sender_config/send_test_email_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail'
require 'onetime/mail/smtp2go_client'
require 'domains/logic/base'
require 'domains/logic/sender_config/send_test_email'

RSpec.describe DomainsAPI::Logic::SenderConfig::SendTestEmail do
  # domain_not_provisioned_error? is a pure predicate over the wrapped
  # delivery error, so exercise it on an allocated instance — the full
  # initializer needs an authenticated session/domain context that is
  # irrelevant here.
  let(:logic) { described_class.allocate }

  def delivery_error(original)
    Onetime::Mail::DeliveryError.new('delivery failed', original_error: original, transient: false)
  end

  def smtp2go_error(message, status_code: 200, error_code: 'E_DeliveryFailures')
    Onetime::Mail::Smtp2goClient::APIError.new(message, status_code: status_code, error_code: error_code)
  end

  describe '#domain_not_provisioned_error? (smtp2go)' do
    it 'recognizes the redacted unverified-sender failure envelope (200, E_DeliveryFailures)' do
      original = smtp2go_error('SMTP2GO reported 1 failed recipient(s): re***@e***.com: unable to verify sender')

      expect(logic.send(:domain_not_provisioned_error?, delivery_error(original))).to be true
    end

    it 'does not match unrelated per-recipient failures with the same error_code' do
      original = smtp2go_error('SMTP2GO reported 1 failed recipient(s): re***@e***.com: mailbox unavailable')

      expect(logic.send(:domain_not_provisioned_error?, delivery_error(original))).to be false
    end

    it 'does not match other smtp2go API errors carrying similar wording' do
      original = smtp2go_error(
        'unable to verify sender',
        status_code: 400,
        error_code: 'E_ApiResponseCodes.NON_VALIDATING_IN_PAYLOAD',
      )

      expect(logic.send(:domain_not_provisioned_error?, delivery_error(original))).to be false
    end

    it 'returns false when the delivery error carries no original error' do
      expect(logic.send(:domain_not_provisioned_error?, delivery_error(nil))).to be false
    end
  end
end
