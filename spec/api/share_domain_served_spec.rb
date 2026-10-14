# spec/api/share_domain_served_spec.rb
#
# frozen_string_literal: true

# Secret creation accepts a custom share_domain only when the domain is
# served as a tenant domain (CustomDomain#served_as_tenant?), the same answer
# DomainStrategy classifies the host by. A link on any other domain would
# open to a 404. This holds whatever features.domains.require_verified says;
# require_verified, when on, still also requires the verified flag.
#
# V1 and V2 each carry their own validate_domain_verification, so both are
# driven here through validate_domain_access, the entry point secret creation
# calls. The domain records are real, unsaved CustomDomain instances; only
# the lookup, the membership check and the homepage gate (datastore reads) are
# stubbed.

require 'spec_helper'
require 'v1/logic'
require 'v2/logic'

RSpec.describe 'share_domain on a custom domain that is not served' do
  let(:host) { 'links.acme-share.com' }

  before(:all) { Onetime.boot! :test }

  before { Onetime::CustomDomain.reset_serving_policy! }

  after { Onetime::CustomDomain.reset_serving_policy! }

  # @param overrides [Hash] features.domains keys to set on a copy of OT.conf
  def configure_domains(**overrides)
    conf    = YAML.load(YAML.dump(OT.conf))
    domains = ((conf['features'] ||= {})['domains'] ||= {})
    { 'require_verified' => false, 'serve_unverified' => false }.merge(overrides.transform_keys(&:to_s))
      .each { |key, value| domains[key] = value }
    allow(OT).to receive(:conf).and_return(conf)
  end

  def domain_record(ownership_verified: nil)
    record                    = Onetime::CustomDomain.new(display_domain: host, org_id: 'org-1')
    record.ownership_verified = ownership_verified unless ownership_verified.nil?
    # The caller is a member of the owning organization: permission is not
    # what these examples are about.
    allow(record).to receive_messages(accessible_by?: true, allow_public_secret_creation?: false)
    allow(Onetime::CustomDomain).to receive(:from_display_domain).with(host).and_return(record)
    record
  end

  let(:member) do
    double('Customer', anonymous?: false, custid: 'cust-1', objid: 'cust-1', extid: 'ur-1', planid: 'basic')
  end

  def v1_logic
    logic = V1::Logic::Secrets::ConcealSecret.allocate
    logic.instance_variable_set(:@cust, member)
    logic.instance_variable_set(:@share_domain, host)
    logic
  end

  def v2_logic
    logic = V2::Logic::Secrets::ConcealSecret.allocate
    logic.instance_variable_set(:@cust, member)
    logic.instance_variable_set(:@share_domain, host)
    logic
  end

  {
    'V1' => :v1_logic,
    'V2' => :v2_logic,
  }.each do |version, builder|
    describe "#{version} validate_domain_access" do
      def access(logic)
        logic.send(:validate_domain_access, host)
        :accepted
      rescue Onetime::FormError => ex
        ex.message
      end

      context 'under a strategy that proves ownership (approximated)' do
        it 'refuses a domain whose ownership is not verified, with require_verified off' do
          configure_domains(validation_strategy: 'approximated')
          domain_record

          expect(access(send(builder))).to eq("Custom domain is not verified: #{host}")
        end

        it 'accepts a domain whose ownership is verified' do
          configure_domains(validation_strategy: 'approximated')
          domain_record(ownership_verified: true)

          expect(access(send(builder))).to eq(:accepted)
        end

        it 'accepts an unverified domain when features.domains.serve_unverified is true' do
          configure_domains(validation_strategy: 'approximated', serve_unverified: true)
          domain_record

          expect(access(send(builder))).to eq(:accepted)
        end

        it 'still applies require_verified on top of serve_unverified' do
          configure_domains(validation_strategy: 'approximated', serve_unverified: true, require_verified: true)
          domain_record

          expect(access(send(builder))).to eq("Custom domain is not verified: #{host}")
        end
      end

      context 'under passthrough' do
        it 'accepts an owned domain that was never verified' do
          configure_domains(validation_strategy: 'passthrough')
          domain_record

          expect(access(send(builder))).to eq(:accepted)
        end

        it 'refuses it when require_verified is on, as before' do
          configure_domains(validation_strategy: 'passthrough', require_verified: true)
          domain_record

          expect(access(send(builder))).to eq("Custom domain is not verified: #{host}")
        end
      end
    end
  end

  it 'gives V2 callers the domain_unverified error type' do
    configure_domains(validation_strategy: 'approximated')
    domain_record

    expect { v2_logic.send(:validate_domain_access, host) }
      .to raise_error(Onetime::FormError) { |ex| expect(ex.error_type).to eq('domain_unverified') }
  end
end
