# spec/unit/onetime/mail/delivery_suppression_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'net/smtp'
require 'onetime/mail/mailer'

# Unit tests for the deliverability hooks in Onetime::Mail::Delivery::Base#deliver
# — the single chokepoint every backend's send converges on:
#
#   1. Outbound suppression guard: suppressed recipients are SKIPPED (no
#      perform_delivery, no emails_sent tick) and the skip is counted.
#   2. Fail-open contract: a broken suppression store must never block a send.
#   3. Synchronous hard bounces (SMTP 5xx at send time) land in the
#      deliverability event feed; other failures do not.
RSpec.describe Onetime::Mail::Delivery::Base do
  # Minimal concrete backend: records perform_delivery calls, optionally raises.
  let(:backend_class) do
    Class.new(described_class) do
      attr_reader :performed

      def perform_delivery(email)
        (@performed ||= []) << email
        raise @failure if @failure

        :provider_response
      end

      def fail_with(error)
        @failure = error
      end

      # Anonymous classes have a nil name; logging derives the provider from it.
      def provider_name
        'TestBackend'
      end
    end
  end

  let(:backend) { backend_class.new }
  let(:email) do
    {
      to: 'recipient@example.com',
      from: 'noreply@example.com',
      subject: 'Hello',
      text_body: 'Body',
    }
  end

  def clear_all
    Onetime::EmailSuppression.entries.clear
    Onetime::EmailSuppression.index.clear
    Onetime::EmailSuppression.events.clear
    Onetime::EmailSuppression.sends_skipped.clear
  end

  before { clear_all }
  after  { clear_all }

  describe 'outbound suppression guard' do
    it 'delivers normally when the recipient is not suppressed' do
      expect(backend.deliver(email)).to eq(:provider_response)
      expect(backend.performed.length).to eq(1)
      expect(Onetime::EmailSuppression.sends_skipped.value).to eq(0)
    end

    it 'skips a suppressed recipient: no delivery, no sent metric, one counted skip' do
      Onetime::EmailSuppression.suppress!(address: 'recipient@example.com', reason: 'bounce')
      before_sent = Onetime::Customer.emails_sent.value

      expect(backend.deliver(email)).to be_nil

      expect(backend.performed).to be_nil
      expect(Onetime::Customer.emails_sent.value).to eq(before_sent)
      expect(Onetime::EmailSuppression.sends_skipped.value).to eq(1)
    end

    it 'matches case-insensitively via address normalization' do
      Onetime::EmailSuppression.suppress!(address: 'recipient@example.com', reason: 'complaint')

      expect(backend.deliver(email.merge(to: 'Recipient@Example.COM'))).to be_nil
      expect(backend.performed).to be_nil
    end

    it 'FAILS OPEN: a broken suppression store never blocks the send' do
      Onetime::EmailSuppression.suppress!(address: 'recipient@example.com', reason: 'bounce')
      allow(Onetime::EmailSuppression).to receive(:skip_send?)
        .and_raise(Redis::CannotConnectError, 'down')

      expect(backend.deliver(email)).to eq(:provider_response)
      expect(backend.performed.length).to eq(1)
    end

    it 'checks each mailbox in an RFC 5322 list, even quoted names with commas' do
      # A naive comma split would mangle the quoted display name and miss the
      # suppressed mailbox; the mail-gem parser extracts it correctly.
      Onetime::EmailSuppression.suppress!(address: 'blocked@example.com', reason: 'bounce')
      to = '"Doe, John" <ok@example.com>, blocked@example.com'

      expect(backend.deliver(email.merge(to: to))).to be_nil
      expect(backend.performed).to be_nil
    end
  end

  describe 'synchronous hard bounce recording' do
    it 'records an SMTP 5xx rejection as a bounce event (and still raises)' do
      backend.fail_with(Net::SMTPFatalError.new('550 5.1.1 user unknown'))

      expect { backend.deliver(email) }.to raise_error(Onetime::Mail::DeliveryError)

      events = Onetime::EmailSuppression.recent_events(5)
      expect(events.length).to eq(1)
      expect(events.first).to include(
        'address' => 'recipient@example.com',
        'kind' => 'bounce',
        'reason' => '550 5.1.1 user unknown',
      )
      expect(events.first['source']).to end_with('-sync')
    end

    it 'does NOT suppress the address from a single synchronous failure' do
      backend.fail_with(Net::SMTPFatalError.new('550 5.1.1 user unknown'))

      expect { backend.deliver(email) }.to raise_error(Onetime::Mail::DeliveryError)

      expect(Onetime::EmailSuppression.suppressed?('recipient@example.com')).to be(false)
    end

    it 'ignores sender-side failures (network errors are not bounces)' do
      backend.fail_with(Errno::ECONNREFUSED.new)

      expect { backend.deliver(email) }.to raise_error(Onetime::Mail::DeliveryError)

      expect(Onetime::EmailSuppression.event_count).to eq(0)
    end

    it 'never masks the delivery error when the feed write itself fails' do
      backend.fail_with(Net::SMTPFatalError.new('550 nope'))
      allow(Onetime::EmailSuppression).to receive(:record_event)
        .and_raise(Redis::CannotConnectError, 'down')

      expect { backend.deliver(email) }.to raise_error(Onetime::Mail::DeliveryError, /550 nope/)
    end
  end
end
