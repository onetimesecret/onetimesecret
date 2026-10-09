# frozen_string_literal: true

require 'spec_helper'
require 'onetime/signup_validation'

RSpec.describe Onetime::SignupValidation do
  let(:host) { 'secrets.acme.com' }
  let(:email) { 'user@global.example.com' }
  let(:domain) { instance_double(Onetime::CustomDomain, identifier: 'domain-acme') }
  let(:config) do
    instance_double(Onetime::CustomDomain::SignupConfig, enabled?: true, valid_signup_email?: false)
  end
  let(:lookup) { Onetime::CustomDomain::Lookup.found(host, domain) }

  before do
    allow(OT).to receive(:conf).and_return(
      'site' => { 'authentication' => { 'allowed_signup_domains' => ['global.example.com'] } },
    )
    allow(OT).to receive(:le)
    allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id)
      .with('domain-acme').and_return(config)
  end

  def validate(lookup: self.lookup, strategy: :custom, display_domain: host)
    described_class.valid_signup_email?(
      email, display_domain: display_domain,
      custom_domain_lookup: lookup, domain_strategy: strategy,
    )
  end

  it 'uses the shared tenant record instead of a second domain read (F1)' do
    expect(Onetime::CustomDomain).not_to receive(:load_by_display_domain)
    expect(Onetime::CustomDomain).not_to receive(:from_display_domain)

    expect(validate).to be(false)
    expect(config).to have_received(:valid_signup_email?).with(email)
  end

  it 'accepts an email allowed by the tenant policy' do
    allow(config).to receive(:valid_signup_email?).with(email).and_return(true)
    expect(validate).to be(true)
  end

  it 'matches the shared host case-insensitively like SignupConfigResolution' do
    expect(Onetime::CustomDomain).not_to receive(:from_display_domain)
    expect(validate(display_domain: host.upcase)).to be(false)
  end

  it 'does not apply a lookup from another tenant' do
    other_lookup = Onetime::CustomDomain::Lookup.found('other.example.com', domain)
    expect(Onetime::CustomDomain).to receive(:from_display_domain).with(host).and_return(nil)
    expect(Onetime::CustomDomain::SignupConfig).not_to receive(:find_by_domain_id)

    expect(validate(lookup: other_lookup)).to be(true)
  end

  it 'preserves shared absence without looking up a newly appeared tenant' do
    expect(Onetime::CustomDomain).not_to receive(:from_display_domain)
    expect(validate(lookup: Onetime::CustomDomain::Lookup.absent(host))).to be(true)
  end

  it 'uses global policy when there is no display domain' do
    expect(Onetime::CustomDomain).not_to receive(:from_display_domain)
    expect(validate(lookup: nil, display_domain: nil)).to be(true)
    expect(described_class.valid_signup_email?('user@blocked.com')).to be(false)
  end

  it 'uses global policy when the tenant config is absent' do
    allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id).and_return(nil)
    expect(validate).to be(true)
  end

  it 'uses global policy when the tenant config is disabled' do
    allow(config).to receive(:enabled?).and_return(false)
    expect(config).not_to receive(:valid_signup_email?)
    expect(validate).to be(true)
  end

  it 'uses a raising lookup when no request lookup is supplied' do
    expect(Onetime::CustomDomain).to receive(:from_display_domain).with(host).and_return(domain)
    expect(validate(lookup: nil)).to be(false)
  end

  [:custom, :invalid, nil].each do |strategy|
    it "fails closed on shared lookup failure for #{strategy.inspect}" do
      failed = Onetime::CustomDomain::Lookup.read_failed(host, Redis::CannotConnectError.new('unavailable'))
      expect(Onetime::CustomDomain).not_to receive(:from_display_domain)
      expect { validate(lookup: failed, strategy: strategy) }.to raise_error(Onetime::SignupPolicyUnavailable)
    end

    it "fails closed on a fresh lookup failure for #{strategy.inspect}" do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_raise(Redis::CannotConnectError)
      expect { validate(lookup: nil, strategy: strategy) }.to raise_error(Onetime::SignupPolicyUnavailable)
    end

    it "fails closed on a config read failure for #{strategy.inspect}" do
      allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id).and_raise(Redis::CannotConnectError)
      expect { validate(strategy: strategy) }.to raise_error(Onetime::SignupPolicyUnavailable)
    end
  end

  [:canonical, 'subdomain'].each do |strategy|
    it "preserves global policy on an operator-host lookup failure for #{strategy.inspect}" do
      failed = Onetime::CustomDomain::Lookup.read_failed(host, Redis::CannotConnectError.new('unavailable'))
      expect(validate(lookup: failed, strategy: strategy)).to be(true)
      expect(described_class.valid_signup_email?(
        'user@blocked.com', display_domain: host, custom_domain_lookup: failed, domain_strategy: strategy,
      )).to be(false)
    end

    it "preserves global policy on an operator-host config failure for #{strategy.inspect}" do
      allow(Onetime::CustomDomain::SignupConfig).to receive(:find_by_domain_id).and_raise(Redis::CannotConnectError)
      expect(validate(strategy: strategy)).to be(true)
    end
  end
end
