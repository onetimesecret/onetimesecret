# apps/api/domains/spec/logic/signin_config/audit_logger_spec.rb
#
# frozen_string_literal: true

# Unit tests for SigninConfig::AuditLogger.
#
# The AuditLogger module provides structured logging for signin
# config changes. Tests cover:
#   - log_signin_audit_event payload structure
#   - extract_ip_address from strategy_result metadata
#
# RUN:
#   pnpm run test:rspec apps/api/domains/spec/logic/signin_config/audit_logger_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::SigninConfig::AuditLogger do
  # The AuditLogger mixin calls respond_to?(:strategy_result) which checks
  # public visibility by default. In production, strategy_result is a public
  # attr_reader on Logic::Base. We mirror that here.
  let(:host_class) do
    Class.new do
      include DomainsAPI::Logic::SigninConfig::AuditLogger

      attr_accessor :strategy_result_mock

      def strategy_result
        strategy_result_mock
      end
    end
  end

  let(:host) { host_class.new }

  let(:domain) do
    instance_double(
      Onetime::CustomDomain,
      identifier: 'test_domain_id_123',
      display_domain: 'secrets.acme.com',
    )
  end

  let(:org) do
    instance_double(
      Onetime::Organization,
      objid: 'test_org_objid_456',
      extid: 'test_org_extid_789',
    )
  end

  let(:actor) do
    instance_double(
      Onetime::Customer,
      custid: 'test_cust_id_abc',
      email: 'admin@acme.com',
    )
  end

  describe '#log_signin_audit_event' do
    it 'logs with the DOMAIN_SIGNIN_AUDIT tag' do
      expect(OT).to receive(:info).with(
        a_string_matching(/\[DOMAIN_SIGNIN_AUDIT\]/),
        anything,
      )

      host.log_signin_audit_event(
        event: :domain_signin_config_created,
        domain: domain,
        org: org,
        actor: actor,
      )
    end

    it 'includes the event name as a string in the log tag' do
      expect(OT).to receive(:info).with(
        a_string_including('domain_signin_config_created'),
        anything,
      )

      host.log_signin_audit_event(
        event: :domain_signin_config_created,
        domain: domain,
        org: org,
        actor: actor,
      )
    end

    it 'includes domain, org, and actor identifiers in JSON payload' do
      captured_payload = nil
      allow(OT).to receive(:info) do |_msg, json_str|
        captured_payload = JSON.parse(json_str)
      end

      host.log_signin_audit_event(
        event: :domain_signin_config_replaced,
        domain: domain,
        org: org,
        actor: actor,
      )

      expect(captured_payload['domain_id']).to eq('test_domain_id_123')
      expect(captured_payload['domain_display']).to eq('secrets.acme.com')
      expect(captured_payload['org_id']).to eq('test_org_objid_456')
      expect(captured_payload['org_extid']).to eq('test_org_extid_789')
      expect(captured_payload['actor_id']).to eq('test_cust_id_abc')
      expect(captured_payload['actor_email']).to eq('admin@acme.com')
    end

    it 'includes a timestamp in the payload' do
      captured_payload = nil
      allow(OT).to receive(:info) do |_msg, json_str|
        captured_payload = JSON.parse(json_str)
      end

      host.log_signin_audit_event(
        event: :domain_signin_config_created,
        domain: domain,
        org: org,
        actor: actor,
      )

      expect(captured_payload['timestamp']).to be_a(Integer)
      expect(captured_payload['timestamp']).to be > 0
    end

    it 'includes details when provided' do
      captured_payload = nil
      allow(OT).to receive(:info) do |_msg, json_str|
        captured_payload = JSON.parse(json_str)
      end

      host.log_signin_audit_event(
        event: :domain_signin_config_replaced,
        domain: domain,
        org: org,
        actor: actor,
        details: { 'changed_fields' => %w[enabled sso_enabled] },
      )

      expect(captured_payload['details']).to eq({ 'changed_fields' => %w[enabled sso_enabled] })
    end

    it 'omits details when empty hash provided' do
      captured_payload = nil
      allow(OT).to receive(:info) do |_msg, json_str|
        captured_payload = JSON.parse(json_str)
      end

      host.log_signin_audit_event(
        event: :domain_signin_config_created,
        domain: domain,
        org: org,
        actor: actor,
        details: {},
      )

      expect(captured_payload).not_to have_key('details')
    end

    it 'omits details when nil provided' do
      captured_payload = nil
      allow(OT).to receive(:info) do |_msg, json_str|
        captured_payload = JSON.parse(json_str)
      end

      host.log_signin_audit_event(
        event: :domain_signin_config_created,
        domain: domain,
        org: org,
        actor: actor,
        details: nil,
      )

      expect(captured_payload).not_to have_key('details')
    end

    context 'event type names' do
      %i[
        domain_signin_config_created
        domain_signin_config_replaced
        domain_signin_config_deleted
        domain_signin_config_enabled
        domain_signin_config_disabled
      ].each do |event_name|
        it "accepts #{event_name}" do
          expect(OT).to receive(:info).with(
            a_string_including(event_name.to_s),
            anything,
          )

          host.log_signin_audit_event(
            event: event_name,
            domain: domain,
            org: org,
            actor: actor,
          )
        end
      end
    end
  end

  describe '#extract_ip_address' do
    it 'returns nil when strategy_result is not available' do
      # host does not have strategy_result_mock set, and
      # respond_to?(:strategy_result) returns true because the method exists
      # but the mock is nil. The method returns nil.
      host.strategy_result_mock = nil
      expect(host.send(:extract_ip_address)).to be_nil
    end

    it 'returns nil when strategy_result has no metadata' do
      result_mock = double('strategy_result')
      allow(result_mock).to receive(:respond_to?).with(:metadata).and_return(false)
      host.strategy_result_mock = result_mock
      expect(host.send(:extract_ip_address)).to be_nil
    end

    it 'returns IP from strategy_result metadata' do
      result_mock = double('strategy_result', metadata: { ip: '192.168.1.42' })
      host.strategy_result_mock = result_mock
      expect(host.send(:extract_ip_address)).to eq('192.168.1.42')
    end
  end
end
