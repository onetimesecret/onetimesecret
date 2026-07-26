# spec/unit/onetime/jobs/enqueue_email_locale_normalization_spec.rb
#
# frozen_string_literal: true

# #3812 regression: enqueue sites must not queue emails with a blank locale.
#
# Customer locales load as "" from Redis (Familia string fields default to the
# empty string), which is truthy and slips past a bare
# `record.locale || OT.default_locale`. Every enqueue site normalizes with
# `locale = OT.default_locale if locale.to_s.strip.empty?` instead.
#
# This file covers one representative per remaining call-site shape; the other
# shapes are pinned elsewhere:
# - Rodauth hooks: spec/integration/full/hooks/account_lifecycle_spec.rb
# - Worker sink:   spec/integration/all/jobs/workers/email_worker_spec.rb
# - `locale || cust.locale` chain: apps/api/organizations/spec/logic/invitations/create_invitation_spec.rb
# - Record-sourced locale:         apps/api/organizations/spec/logic/members/update_member_role_spec.rb
#
# Instances are `allocate`d with only the ivars the notify method reads, per
# the precedent in spec/unit/onetime/logic/require_entitlement_spec.rb.
#
# Run: pnpm run test:rspec spec/unit/onetime/jobs/enqueue_email_locale_normalization_spec.rb

require 'spec_helper'
require 'organizations/logic'
require 'auth/operations/disable_mfa'
# Handlers self-register with ProcessWebhookEvent when their class body loads.
require 'billing/operations/process_webhook_event'
require 'billing/operations/webhook_handlers/subscription_updated'
require 'v3/logic/feedback'

RSpec.describe 'Email enqueue locale normalization (#3812)' do
  def capture_enqueued_payloads
    captured = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |_template, payload, **_kwargs|
      captured << payload
      nil
    end
    captured
  end

  describe 'OrganizationAPI::Logic::Organizations::DeleteOrganization#notify_members_deleted' do
    # Recipient locales are captured from member records before deletion, so a
    # blank stored locale arrives here as "" inside the recipients hash.
    let(:logic) do
      instance = OrganizationAPI::Logic::Organizations::DeleteOrganization.allocate
      instance.instance_variable_set(:@cust, double('Customer', email: 'owner@example.com'))
      instance
    end

    it 'normalizes blank recipient locales and preserves set ones' do
      captured   = capture_enqueued_payloads
      recipients = [
        { email: 'blank@example.com', locale: '' },
        { email: 'spaces@example.com', locale: '   ' },
        { email: 'missing@example.com', locale: nil },
        { email: 'set@example.com', locale: 'de' },
      ]

      logic.send(:notify_members_deleted, recipients, 'Doomed Org')

      expect(captured.map { |payload| payload[:locale] })
        .to eq([OT.default_locale, OT.default_locale, OT.default_locale, 'de'])
    end
  end

  describe 'Auth::Operations::DisableMfa#notify_customer' do
    def enqueued_mfa_disabled_locale(customer)
      captured  = capture_enqueued_payloads
      operation = Auth::Operations::DisableMfa.allocate
      operation.instance_variable_set(:@email, 'user@example.com')
      operation.instance_variable_set(:@customer, customer)

      operation.send(:notify_customer)

      expect(captured.size).to eq(1),
        "Expected exactly one :mfa_disabled email, got #{captured.size}"
      captured.first[:locale]
    end

    it 'falls back to the default locale when the customer locale is blank' do
      customer = double('Customer', locale: '')
      expect(enqueued_mfa_disabled_locale(customer)).to eq(OT.default_locale)
    end

    it 'falls back to the default locale when the customer locale is whitespace-only' do
      customer = double('Customer', locale: '   ')
      expect(enqueued_mfa_disabled_locale(customer)).to eq(OT.default_locale)
    end

    it 'falls back to the default locale when the customer has no locale method' do
      customer = double('AuthAccount')
      expect(enqueued_mfa_disabled_locale(customer)).to eq(OT.default_locale)
    end

    it 'carries a set customer locale through to the payload' do
      customer = double('Customer', locale: 'fr')
      expect(enqueued_mfa_disabled_locale(customer)).to eq('fr')
    end
  end

  describe 'Billing::Operations::WebhookHandlers::SubscriptionUpdated#notify_subscription_changed' do
    def enqueued_subscription_changed_locale(owner)
      captured = capture_enqueued_payloads
      handler  = Billing::Operations::WebhookHandlers::SubscriptionUpdated.allocate
      org      = double('Organization', owner: owner)

      handler.send(:notify_subscription_changed, org, 'basic', 'premium')

      expect(captured.size).to eq(1),
        "Expected exactly one :subscription_changed email, got #{captured.size}"
      captured.first[:locale]
    end

    it 'falls back to the default locale when the owner locale is blank' do
      owner = double('Customer', email: 'owner@example.com', locale: '')
      expect(enqueued_subscription_changed_locale(owner)).to eq(OT.default_locale)
    end

    it 'carries a set owner locale through to the payload' do
      owner = double('Customer', email: 'owner@example.com', locale: 'fr')
      expect(enqueued_subscription_changed_locale(owner)).to eq('fr')
    end
  end

  describe 'V3::Logic::ReceiveFeedback#send_feedback' do
    # Here `locale` comes from Logic::Base (request context / params), so a
    # blank request locale ("") is the failure mode rather than a record load.
    def enqueued_feedback_locale(request_locale)
      captured = capture_enqueued_payloads
      customer = double('Customer', anonymous?: false, email: 'user@example.com', extid: 'ur_user_extid')

      logic = V3::Logic::ReceiveFeedback.allocate
      logic.instance_variable_set(:@cust, customer)
      logic.instance_variable_set(:@tz, 'UTC')
      logic.instance_variable_set(:@version, '1.0.0')
      logic.instance_variable_set(:@display_domain, 'onetime.example')
      logic.instance_variable_set(:@domain_strategy, :canonical)
      logic.instance_variable_set(:@locale, request_locale)

      logic.send(:send_feedback, 'admin@example.com', customer, 'hello world')

      expect(captured.size).to eq(1),
        "Expected exactly one :feedback_email, got #{captured.size}"
      captured.first[:locale]
    end

    it 'falls back to the default locale when the request locale is blank' do
      expect(enqueued_feedback_locale('')).to eq(OT.default_locale)
    end

    it 'falls back to the default locale when the request locale is whitespace-only' do
      expect(enqueued_feedback_locale('   ')).to eq(OT.default_locale)
    end

    it 'carries a set request locale through to the payload' do
      expect(enqueued_feedback_locale('fr')).to eq('fr')
    end
  end
end
