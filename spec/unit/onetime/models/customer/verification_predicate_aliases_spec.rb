# spec/unit/onetime/models/customer/verification_predicate_aliases_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# The deprecated names answer exactly as the renamed predicates do:
# verified? is account_verified?, email_verified? is verified_by_email_link?.
RSpec.describe Onetime::Customer, 'deprecated verification predicate aliases' do
  def customer(verified:, verified_by:, role: 'customer')
    cust             = described_class.new(email: "alias-#{SecureRandom.hex(4)}@example.com")
    cust.verified    = verified
    cust.verified_by = verified_by
    cust.role        = role
    cust
  end

  it 'defines verified? as an alias of account_verified?' do
    expect(described_class.instance_method(:verified?).original_name).to eq(:account_verified?)
  end

  it 'defines email_verified? as an alias of verified_by_email_link?' do
    expect(described_class.instance_method(:email_verified?).original_name).to eq(:verified_by_email_link?)
  end

  states = [true, false].product([*described_class::VERIFIED_BY_VALUES, nil], %w[customer anonymous])

  states.each do |verified, verified_by, role|
    context "verified=#{verified} verified_by=#{verified_by.inspect} role=#{role}" do
      let(:cust) { customer(verified: verified, verified_by: verified_by, role: role) }

      it 'answers verified? == account_verified?' do
        expect(cust.verified?).to eq(cust.account_verified?)
      end

      it 'answers email_verified? == verified_by_email_link?' do
        expect(cust.email_verified?).to eq(cust.verified_by_email_link?)
      end
    end
  end

  it 'is true for verified_by_email_link? only with the email stamp' do
    expect(customer(verified: true, verified_by: 'email').verified_by_email_link?).to be(true)
    expect(customer(verified: true, verified_by: 'invite_token').verified_by_email_link?).to be(false)
    expect(customer(verified: false, verified_by: 'email').verified_by_email_link?).to be(false)
  end
end
