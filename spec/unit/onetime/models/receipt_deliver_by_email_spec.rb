# spec/unit/onetime/models/receipt_deliver_by_email_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for Receipt#deliver_by_email domain_id resolution.
#
# Verifies that deliver_by_email resolves share_domain to a domain_id
# via CustomDomain.display_domains and passes it to Publisher.enqueue_email.
#
# Gap 4: Receipt delivery with domain context -- ensures the domain_id
# keyword flows through to the Publisher so the email worker can look up
# per-domain sender config (MailerConfig).
#
RSpec.describe Onetime::Receipt do
  describe '#deliver_by_email' do
    let(:receipt) do
      r = Onetime::Receipt.new
      r.state = 'new'
      # Give it a stable identifier for log messages
      allow(r).to receive(:identifier).and_return('receipt-test-123')
      allow(r).to receive(:shortid).and_return('receipt-t')
      r
    end

    let(:customer) do
      instance_double(Onetime::Customer,
        email: 'sender@example.com',
        obscure_email: 's***r@example.com')
    end

    let(:secret) do
      instance_double(Onetime::Secret,
        identifier: 'secret-abc-456',
        share_domain: share_domain,
        objid: 'secret-abc-456',
        shortid: 'secret-a')
    end

    let(:locale) { 'en' }
    let(:recipient_email) { 'recipient@example.com' }

    # Stub the bang writer so it doesn't hit Redis
    before do
      allow(receipt).to receive(:recipients!)
      allow(receipt).to receive(:save).and_return(true)
    end

    context 'when share_domain maps to a known CustomDomain' do
      let(:share_domain) { 'secrets.acme.com' }
      let(:expected_domain_id) { 'customdomain:abc123' }

      before do
        display_domains = double('display_domains')
        allow(Onetime::CustomDomain).to receive(:display_domains).and_return(display_domains)
        allow(display_domains).to receive(:get).with(share_domain).and_return(expected_domain_id)
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
      end

      it 'passes the resolved domain_id to Publisher.enqueue_email' do
        receipt.deliver_by_email(customer, locale, secret, [recipient_email])

        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
          :secret_link,
          hash_including(
            secret_key: 'secret-abc-456',
            share_domain: share_domain,
            recipient: recipient_email,
            sender_email: 'sender@example.com',
            locale: 'en'
          ),
          domain_id: expected_domain_id
        )
      end
    end

    context 'when share_domain is nil' do
      let(:share_domain) { nil }

      before do
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
      end

      it 'passes nil as domain_id to Publisher.enqueue_email' do
        receipt.deliver_by_email(customer, locale, secret, [recipient_email])

        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
          :secret_link,
          hash_including(
            secret_key: 'secret-abc-456',
            recipient: recipient_email
          ),
          domain_id: nil
        )
      end
    end

    context 'when share_domain is an empty string' do
      let(:share_domain) { '' }

      before do
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
      end

      it 'passes nil as domain_id to Publisher.enqueue_email' do
        receipt.deliver_by_email(customer, locale, secret, [recipient_email])

        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
          :secret_link,
          hash_including(recipient: recipient_email),
          domain_id: nil
        )
      end
    end

    context 'when share_domain is not registered in display_domains' do
      let(:share_domain) { 'unknown.example.com' }

      before do
        display_domains = double('display_domains')
        allow(Onetime::CustomDomain).to receive(:display_domains).and_return(display_domains)
        allow(display_domains).to receive(:get).with(share_domain).and_return(nil)
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
      end

      it 'passes nil as domain_id to Publisher.enqueue_email' do
        receipt.deliver_by_email(customer, locale, secret, [recipient_email])

        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
          :secret_link,
          hash_including(recipient: recipient_email),
          domain_id: nil
        )
      end
    end

    context 'when display_domains.get raises an error' do
      let(:share_domain) { 'broken.example.com' }

      before do
        display_domains = double('display_domains')
        allow(Onetime::CustomDomain).to receive(:display_domains).and_return(display_domains)
        allow(display_domains).to receive(:get).with(share_domain).and_raise(Redis::ConnectionError, 'Connection refused')
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
      end

      it 'falls back to nil domain_id (fault-tolerant)' do
        receipt.deliver_by_email(customer, locale, secret, [recipient_email])

        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
          :secret_link,
          hash_including(recipient: recipient_email),
          domain_id: nil
        )
      end
    end

    context 'when eaddrs is nil' do
      let(:share_domain) { 'secrets.acme.com' }

      it 'returns early without enqueuing email' do
        expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)
        receipt.deliver_by_email(customer, locale, secret, nil)
      end
    end

    context 'when eaddrs is empty' do
      let(:share_domain) { 'secrets.acme.com' }

      it 'returns early without enqueuing email' do
        expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_email)
        receipt.deliver_by_email(customer, locale, secret, [])
      end
    end
  end
end
