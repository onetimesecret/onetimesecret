# spec/unit/onetime/models/customer/notifiable_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# Customer#notifiable?: may this customer receive owner notification mail
# (the reveal notice and the expiration warning). Non-anonymous, non-empty
# email, and verified by any provenance; deliberately not mailbox_verified?.
RSpec.describe Onetime::Customer, '#notifiable?' do
  def customer(verified: true, verified_by: 'email', email: "notifiable-#{SecureRandom.hex(4)}@example.com")
    cust             = described_class.new(email: email)
    cust.verified    = verified
    cust.verified_by = verified_by
    cust
  end

  described_class::VERIFIED_BY_VALUES.each do |provenance|
    it "is true for a verified customer stamped #{provenance}" do
      expect(customer(verified_by: provenance).notifiable?).to be(true)
    end
  end

  it 'is true for an IdP-asserted (sso) account although mailbox_verified? is false' do
    cust = customer(verified_by: 'sso')
    expect(cust.mailbox_verified?).to be(false)
    expect(cust.notifiable?).to be(true)
  end

  it 'is true for a verified customer with no provenance (any provenance qualifies)' do
    expect(customer(verified_by: nil).notifiable?).to be(true)
  end

  it 'is false for an SSO account whose verification was held at JIT provisioning' do
    cust                     = customer(verified: false, verified_by: nil)
    cust.verification_hold   = 'idp_unverified'
    cust.provisioning_origin = 'sso_jit'
    expect(cust.verification_held?).to be(true)
    expect(cust.notifiable?).to be(false)
  end

  it 'is false for an unverified customer' do
    expect(customer(verified: false, verified_by: nil).notifiable?).to be(false)
  end

  it 'is false for an anonymous customer, even when the stored flag reads verified' do
    cust      = customer
    cust.role = 'anonymous'
    expect(cust.notifiable?).to be(false)
  end

  it 'is false for a blank or missing email' do
    expect(customer(email: '').notifiable?).to be(false)
    expect(customer(email: nil).notifiable?).to be(false)
  end

  it 'ignores the per-notice reveal preference' do
    cust                  = customer
    cust.notify_on_reveal = 'false'
    expect(cust.notifiable?).to be(true)
  end
end
