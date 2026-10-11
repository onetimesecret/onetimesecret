# spec/unit/onetime/models/customer/mailbox_proof_secret_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# Customer#mailbox_proof_secret? (#4735): which verification secret, when
# revealed, proves control of the owner's CURRENT mailbox. The secret's own
# kind decides; a secret minted before the kind was recorded is classified by
# how it was minted (receipt-backed = the account-verification link) and,
# failing that, by whether the account recorded it as its own link. A missing
# or mismatched pointer is never proof — the pointers only narrow.
#
# Only the two standalone pointers touch the datastore (reset_secret /
# pending_email_change write through immediately); the customer is never
# saved. The predicate reads three attributes of the secret (kind,
# receipt_identifier, identifier), so a double stands in for one — minting a
# real Secret needs the verifiable-id HMAC secret this lane does not set.
RSpec.describe Onetime::Customer do
  let(:customer) { described_class.new(email: "proof-#{SecureRandom.hex(4)}@example.com") }

  after do
    customer.reset_secret.delete!
    customer.pending_email_change.delete!
  end

  def secret(kind: nil, receipt: false)
    double(
      'Secret',
      kind: kind,
      receipt_identifier: (receipt ? "rcpt_#{SecureRandom.hex(4)}" : nil),
      identifier: "sec_#{SecureRandom.hex(8)}",
    )
  end

  describe 'MAILBOX_PROOF_KINDS' do
    it 'names the two links delivered to the current address' do
      expect(Onetime::Secret::MAILBOX_PROOF_KINDS).to contain_exactly('account_verification', 'password_reset')
    end
  end

  describe 'a secret that identifies itself' do
    it 'is never proof when it is the email-change confirmation, pointer or not' do
      s                     = secret(kind: 'email_change', receipt: true)
      customer.reset_secret = s.identifier

      expect(customer.mailbox_proof_secret?(s)).to be false
    end

    %w[account_verification password_reset].each do |kind|
      it "is proof when it is a #{kind} link, whatever the pointers say" do
        s                     = secret(kind: kind)
        customer.reset_secret = 'some-newer-link'

        expect(customer.mailbox_proof_secret?(s)).to be true
      end
    end

    it 'is narrowed, never widened, by the pending email-change pointer' do
      s                             = secret(kind: 'account_verification')
      customer.pending_email_change = s.identifier

      expect(customer.mailbox_proof_secret?(s)).to be false
    end
  end

  describe 'a legacy secret with no kind' do
    it 'is proof when receipt-backed (only send_verification_email mints one)' do
      s = secret(receipt: true)

      expect(customer.mailbox_proof_secret?(s)).to be true
    end

    it 'is proof when receiptless but recorded as the account\'s own link (password reset)' do
      s                     = secret
      customer.reset_secret = s.identifier

      expect(customer.mailbox_proof_secret?(s)).to be true
    end

    it 'is not proof when receiptless and no link is recorded' do
      expect(customer.mailbox_proof_secret?(secret)).to be false
    end

    it 'is not proof when receiptless and a different link is recorded' do
      customer.reset_secret = 'another-secret'

      expect(customer.mailbox_proof_secret?(secret)).to be false
    end

    # F1: two email-change requests before the kind existed left two live
    # confirmation secrets; only the second is on the pointer.
    it 'is not proof when receiptless and superseded on the pending pointer' do
      first                         = secret
      customer.pending_email_change = 'the-second-request'

      expect(customer.mailbox_proof_secret?(first)).to be false
    end

    it 'is not proof when receiptless and still on the pending pointer' do
      s                             = secret
      customer.pending_email_change = s.identifier

      expect(customer.mailbox_proof_secret?(s)).to be false
    end
  end
end
