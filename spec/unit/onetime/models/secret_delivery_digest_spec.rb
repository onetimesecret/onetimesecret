# spec/unit/onetime/models/secret_delivery_digest_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Secret.delivery_digest_for and Secret#delivered_to? (#4754 review, round 3).
# send_verification_email records a keyed digest of the address the welcome
# link is emailed to, so the federation claim its reveal runs can tell whether
# the link proves the account's current address: a link is tied to the
# account, and after an operator changes the address it still reveals. The
# predicate reads delivery_digest alone, so nothing here is saved.
RSpec.describe Onetime::Secret do
  let(:address) { "delivery-#{SecureRandom.hex(4)}@example.com" }

  def link(digest)
    described_class.new.tap { |secret| secret.delivery_digest = digest }
  end

  describe '.delivery_digest_for' do
    it 'digests the normalized address, so case and surrounding space do not matter' do
      expect(described_class.delivery_digest_for("  #{address.upcase} "))
        .to eq(described_class.delivery_digest_for(address))
    end

    it 'gives another address another digest' do
      expect(described_class.delivery_digest_for(address))
        .not_to eq(described_class.delivery_digest_for("other-#{address}"))
    end

    it 'is a hex digest that does not carry the address' do
      digest = described_class.delivery_digest_for(address)

      expect(digest).to match(/\A\h{64}\z/)
      expect(digest).not_to include(address)
    end

    it 'is keyed: an unkeyed hash of the same input differs' do
      unkeyed = OpenSSL::Digest::SHA256.hexdigest("#{described_class::DELIVERY_DIGEST_DOMAIN}:#{address}")

      expect(described_class.delivery_digest_for(address)).not_to eq(unkeyed)
    end

    it 'is nil for a blank address' do
      expect(described_class.delivery_digest_for(nil)).to be_nil
      expect(described_class.delivery_digest_for('   ')).to be_nil
    end
  end

  describe '#delivered_to?' do
    it 'is true for the address the link was sent to, in any case' do
      secret = link(described_class.delivery_digest_for(address))

      expect(secret.delivered_to?(address)).to be(true)
      expect(secret.delivered_to?(address.upcase)).to be(true)
    end

    it 'is false for another address' do
      secret = link(described_class.delivery_digest_for(address))

      expect(secret.delivered_to?("other-#{address}")).to be(false)
    end

    it 'is false for a blank address' do
      secret = link(described_class.delivery_digest_for(address))

      expect(secret.delivered_to?(nil)).to be(false)
      expect(secret.delivered_to?('')).to be(false)
    end

    # A link minted before the digest was written: nothing says which mailbox
    # it proves.
    it 'is false for every address when no delivery address was recorded' do
      expect(link(nil).delivered_to?(address)).to be(false)
      expect(link('').delivered_to?(address)).to be(false)
    end
  end
end
