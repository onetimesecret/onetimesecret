# frozen_string_literal: true

require 'spec_helper'
require 'rodauth'

module Auth; end
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)
Auth::Config.const_set(:Hooks, Module.new) unless Auth::Config.const_defined?(:Hooks, false)

require_relative '../../../config/hooks/account'

RSpec.describe Auth::Config::Hooks::Account do
  describe '.resolve_customer' do
    let(:email) { 'account@example.com' }
    let(:customer) { instance_double(Onetime::Customer) }

    it 'resolves a customer by the account external ID without consulting email' do
      account = { external_id: 'ur_current', email: email }
      allow(Onetime::Customer).to receive(:find_by_extid).with('ur_current').and_return(customer)
      expect(Onetime::Customer).not_to receive(:find_by_email)

      expect(described_class.resolve_customer(account)).to equal(customer)
    end

    it 'fails closed when a nonblank external ID misses even if email matches another customer' do
      account = { external_id: 'ur_missing', email: email }
      allow(Onetime::Customer).to receive(:find_by_extid).with('ur_missing').and_return(nil)
      allow(Onetime::Customer).to receive(:find_by_email).with(email).and_return(customer)

      expect(described_class.resolve_customer(account)).to be_nil
      expect(Onetime::Customer).not_to have_received(:find_by_email)
    end

    it 'falls back to email only when the account external ID is blank' do
      account = { external_id: nil, email: email }
      allow(Onetime::Customer).to receive(:find_by_email).with(email).and_return(customer)
      expect(Onetime::Customer).not_to receive(:find_by_extid)

      expect(described_class.resolve_customer(account)).to equal(customer)
    end
  end
end
