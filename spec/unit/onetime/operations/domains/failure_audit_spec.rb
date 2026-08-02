# spec/unit/onetime/operations/domains/failure_audit_spec.rb
#
# frozen_string_literal: true

# The FAILURE half of the domain ops' audit contract.
#
# Every AdminAuditEvent.record call in these ops sits AFTER the mutation, on
# the success path, so until Onetime::AuditedFailure was applied a create that
# blew up, a refused create, a config upsert rejected by a model setter, and a
# materialize-outcome contract drift all left the admin trail completely empty.
# These are the tests that prove the wrapper fires, records ONE event with the
# byte-identical verb, and re-raises unchanged.
#
# Refusal + raise coverage for Transfer / Repair / DeleteDomainConfig /
# UpsertDomainConfig-through-HTTP lives in the tryouts that already exercise
# them end-to-end (try/unit/operations/domain_toolbox_try.rb,
# try/integration/api/colonel/domain_configs_try.rb). This file covers the ops
# with no incumbent spec of their own.
#
# Message expectations, not store reads: AdminAuditEvent.record swallows its
# own errors and returns nil, so a store read here could pass or fail for
# reasons unrelated to the mechanism.
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/domains/failure_audit_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'onetime/operations/domains/create'
require 'onetime/operations/domains/ensure_domain_configs'
require 'onetime/operations/domains/upsert_domain_config'

RSpec.describe 'domain operations failure auditing' do
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)

  before { allow(Onetime::AdminAuditEvent).to receive(:record) }

  describe Onetime::Operations::Domains::Create do
    let(:org) { double('Organization', objid: 'org-obj-1', extid: 'on_org_ext') }

    def build(domain: 'shop.example.com')
      described_class.new(domain: domain, org: org, actor: actor, request_certificate: false)
    end

    # A rejection mutates nothing, but it is still a refused privileged create.
    # The TARGET is the FQDN, not an extid — the CustomDomain does not exist.
    it 'records ONE result: :failure event for a rejected create, targeting the FQDN' do
      allow(Onetime::CustomDomain).to receive(:valid?).with('bogus').and_return(false)

      result = build(domain: 'bogus').call

      expect(result.status).to eq(:invalid)
      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'domain.create',
        target: 'bogus',
        result: :failure,
        detail: { reason: 'invalid', org_id: 'on_org_ext', display_domain: 'bogus' },
      )
    end

    it 'bounds the failure target so raw operator input cannot write an unbounded string' do
      overlong = "#{'a' * 400}.example.com"
      allow(Onetime::CustomDomain).to receive(:valid?).with(overlong).and_return(false)

      build(domain: overlong).call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        hash_including(target: overlong[0, described_class::MAX_TARGET_LENGTH]),
      )
    end

    # The AuditedFailure mechanism. create! atomically claims the
    # display_domain index and runs BEFORE the success-path record call.
    it 'records ONE result: :failure event when create! raises, and re-raises' do
      allow(Onetime::CustomDomain).to receive(:valid?).and_return(true)
      allow(Onetime::CustomDomain).to receive(:overlaps_canonical_domain?).and_return(false)
      allow(Onetime::CustomDomain).to receive(:parse)
        .and_return(double('CustomDomain', display_domain: 'shop.example.com'))
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(nil)
      allow(Onetime::CustomDomain).to receive(:create!).and_raise(Onetime::Problem, 'index claim failed')

      expect { build.call }.to raise_error(Onetime::Problem, /index claim failed/)

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: actor,
          verb: 'domain.create',
          # The NORMALISED fqdn: validation ran, so it is a better target than
          # the raw input. A broken lambda would silently land as 'unknown'.
          target: 'shop.example.com',
          result: :failure,
          detail: hash_including(
            error: 'Onetime::Problem', message: 'index claim failed',
            org_id: 'on_org_ext', display_domain: 'shop.example.com',
          ),
        ),
      )
    end
  end

  describe Onetime::Operations::Domains::EnsureDomainConfigs do
    let(:domain) { double('CustomDomain', identifier: 'dom-obj-1', extid: 'cd_dom_ext') }
    let(:model)  { double('SigninConfig') }
    let(:registry) { Onetime::CustomDomain::ConfigRegistry }

    before do
      allow(registry).to receive(:credential_required_skips).and_return([])
      allow(registry).to receive(:materializable_slugs).and_return(['signin'])
      allow(registry).to receive(:model_for).with('signin').and_return(model)
      allow(model).to receive(:exists_for_domain?).with('dom-obj-1').and_return(false)
    end

    # The AuditedFailure mechanism. The loop creates records one kind at a
    # time and the success record runs only at the end, so a raise partway
    # leaves already-created records with no trail.
    it 'records ONE result: :failure event on a materialize contract drift, and re-raises' do
      allow(model).to receive(:respond_to?).with(:find_or_create_for_domain).and_return(true)
      allow(model).to receive(:find_or_create_for_domain).and_return([nil, :bogus_outcome])

      expect do
        described_class.new(domain: domain, actor: actor, dry_run: false).call
      end.to raise_error(Onetime::Problem, /Unexpected materialize outcome/)

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: actor,
          verb: 'domain.configs_ensure',
          target: 'cd_dom_ext', # literal: a broken target lambda lands as 'unknown'
          result: :failure,
          # dry_run disambiguates a blown-up preview from a blown-up apply.
          detail: hash_including(error: 'Onetime::Problem', dry_run: false),
        ),
      )
    end

    it 'audits nothing on a dry run (nothing was attempted)' do
      allow(model).to receive(:respond_to?).with(:find_or_create_for_domain).and_return(true)

      result = described_class.new(domain: domain, actor: actor, dry_run: true).call

      expect(result.status).to eq(:planned)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end

  describe Onetime::Operations::Domains::UpsertDomainConfig do
    let(:domain)   { double('CustomDomain', identifier: 'dom-obj-1', extid: 'cd_dom_ext') }
    let(:model)    { double('SignupConfig') }
    let(:existing) { double('SignupConfig record') }
    let(:registry) { Onetime::CustomDomain::ConfigRegistry }

    # The AuditedFailure mechanism. apply_update runs the model setters, which
    # is where validation blows up — after the write path was entered and
    # before the success-path record call.
    it 'records ONE result: :failure event when a model setter raises, and re-raises' do
      allow(registry).to receive(:model_for).with('signup').and_return(model)
      allow(model).to receive(:find_by_domain_id).with('dom-obj-1').and_return(existing)
      allow(registry).to receive(:apply_field).and_raise(Onetime::Problem, 'not a public domain')

      expect do
        described_class.new(
          domain: domain, kind: 'signup',
          attrs: { 'allowed_signup_domains' => ['not_a_domain'] }, actor: actor,
        ).call
      end.to raise_error(Onetime::Problem, /not a public domain/)

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: actor,
          verb: 'domain.config_upsert',
          target: 'cd_dom_ext', # literal: a broken target lambda lands as 'unknown'
          result: :failure,
          # Field NAMES only, never values — recipients/allowlists are
          # semi-sensitive, same rule as the success event.
          detail: hash_including(config: 'signup', changed: ['allowed_signup_domains']),
        ),
      )
    end
  end
end
