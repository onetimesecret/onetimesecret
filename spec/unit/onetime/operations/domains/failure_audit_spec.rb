# spec/unit/onetime/operations/domains/failure_audit_spec.rb
#
# frozen_string_literal: true

# The FAILURE half of the domain ops' audit contract.
#
# Every ColonelAuditEvent.record call in these ops sits AFTER the mutation, on
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
# Message expectations, not store reads: ColonelAuditEvent.record swallows its
# own errors and returns nil, so a store read here could pass or fail for
# reasons unrelated to the mechanism.
#
# The last block pins the module's ONE exception-class special case
# (Onetime::AuditWriteFailure → verb audit.write_failure, #4324). It lives here
# because this is the canonical AuditedFailure spec, and it uses a throwaway
# audited class rather than a domain op: no domain verb is fail-closed, so an
# AuditWriteFailure never originates in one, and the behaviour under test
# belongs to the wrapper rather than to any op.
#
# Run: pnpm run test:rspec spec/unit/onetime/operations/domains/failure_audit_spec.rb

require 'spec_helper'
require 'onetime/audited_failure'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/domains/create'
require 'onetime/operations/domains/ensure_domain_configs'
require 'onetime/operations/domains/upsert_domain_config'

RSpec.describe 'domain operations failure auditing' do
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)

  before { allow(Onetime::ColonelAuditEvent).to receive(:record) }

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
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
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

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
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

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
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

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
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
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
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

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
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

  # The wrapper is verb-preserving for every exception class but one. An
  # Onetime::AuditWriteFailure means the op's OWN audit write failed, and
  # re-reporting it under the op's verb would claim the operation failed —
  # for a destructive op that already completed, and (this write being
  # fail-open, a tick after the blip) usually SUCCESSFULLY. That is an
  # affirmatively wrong record, not a missing one, so it gets its own verb.
  describe Onetime::AuditedFailure do
    # Stands in for any of the 12 fail-closed call sites: same wrapper, same
    # op-supplied detail, raising from inside the wrapped entry method.
    let(:audited_class) do
      Class.new do
        include Onetime::AuditedFailure

        audit_failures :call,
                       verb: 'customer.purge',
                       target: -> { @target },
                       actor: -> { @actor },
                       detail: -> { { email: 'p***@e***.com' } }

        def initialize(actor:, target:, error:)
          @actor  = actor
          @target = target
          @error  = error
        end

        def call
          raise @error
        end
      end
    end

    let(:write_failure) { Onetime::AuditWriteFailure.new(verb: 'customer.purge', target: 'ur_p') }

    def run(error, target: 'ur_p')
      audited_class.new(actor: actor, target: target, error: error).call
    end

    it 'records an AuditWriteFailure under audit.write_failure, not the op verb' do
      expect { run(write_failure) }.to raise_error(Onetime::AuditWriteFailure)

      # Full kwargs, not hash_including: this also pins that no `fail_closed:`
      # is passed. The report of a failed write must never itself fail closed —
      # that would raise a SECOND, untagged AuditWriteFailure into the wrapper.
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'audit.write_failure',
        target: 'ur_p', # the ORIGINAL op's target, carried on the error
        result: :failure,
        detail: hash_including(
          # `failed_verb`, not `reason` — since #4338 `reason` in a detail means
          # operator-supplied justification.
          failed_verb: 'customer.purge',
          error: 'Onetime::AuditWriteFailure',
          email: 'p***@e***.com', # op-supplied detail still rides along
        ),
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record).with(
        hash_including(verb: 'customer.purge'),
      )
    end

    it 're-raises the original AuditWriteFailure instance unchanged' do
      raised = nil
      begin
        run(write_failure)
      rescue Onetime::AuditWriteFailure => ex
        raised = ex
      end

      expect(raised).to be(write_failure)
    end

    # The error's verb/target win because they name the write that actually
    # failed, which need not be the wrapper's own (a nested audited call).
    it 'prefers the failed write\'s verb and target over the wrapper\'s' do
      nested = Onetime::AuditWriteFailure.new(verb: 'membership.remove', target: 'mb_inner')

      expect { run(nested, target: 'ur_outer') }.to raise_error(Onetime::AuditWriteFailure)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          verb: 'audit.write_failure',
          target: 'mb_inner',
          detail: hash_including(failed_verb: 'membership.remove'),
        ),
      )
    end

    # Never downgrade a good target to an empty string.
    it 'falls back to the wrapper-resolved target when the error carries none' do
      blank = Onetime::AuditWriteFailure.new(verb: 'customer.purge', target: '')

      expect { run(blank, target: 'ur_fallback') }.to raise_error(Onetime::AuditWriteFailure)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'audit.write_failure', target: 'ur_fallback'),
      )
    end

    # Existing behaviour, pinned: the special case is ONE class wide.
    it 'still records a non-AuditWriteFailure error under the op\'s own verb' do
      expect { run(Onetime::Problem.new('teardown blew up')) }
        .to raise_error(Onetime::Problem, /teardown blew up/)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'customer.purge',
        target: 'ur_p',
        result: :failure,
        detail: hash_including(error: 'Onetime::Problem', message: 'teardown blew up'),
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record).with(
        hash_including(verb: 'audit.write_failure'),
      )
    end

    # Nesting still records ONCE, innermost wins — the RECORDED_FLAG rides the
    # exception instance, not the verb, so the swapped verb does not open a
    # second write for an outer audited frame re-raising the same error.
    it 'does not re-record a write failure an inner audited frame already recorded' do
      inner = audited_class
      outer = Class.new do
        include Onetime::AuditedFailure
        audit_failures :call, verb: 'organization.delete', target: -> { 'on_outer' }, actor: -> { @actor }

        define_method(:initialize) do |actor:, inner_class:, error:|
          @actor = actor
          @inner = inner_class.new(actor: actor, target: 'ur_p', error: error)
        end

        def call
          @inner.call
        end
      end

      expect { outer.new(actor: actor, inner_class: inner, error: write_failure).call }
        .to raise_error(Onetime::AuditWriteFailure)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once
      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        hash_including(verb: 'audit.write_failure'),
      )
    end
  end
end
