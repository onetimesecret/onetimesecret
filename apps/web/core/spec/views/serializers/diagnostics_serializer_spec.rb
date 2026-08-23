# apps/web/core/spec/views/serializers/diagnostics_serializer_spec.rb
#
# frozen_string_literal: true

# Coverage for DiagnosticsSerializer's pseudonymous actor reference.
#
# The bootstrap payload is the only channel that hands the browser Sentry SDK
# a reference, so this file pins the two directions that can go wrong:
#
#   OMISSION. Anonymous visitors, awaiting-MFA sessions, customers with no
#   readable extid, and installs with no ACCOUNT_ID_SECRET must produce NO
#   `diagnostics_ref` key at all. Absence is the contract — not a null, not an
#   empty string — because an anonymous visitor has no reference to report and
#   an unconfigured install (the default in dev and test) must render exactly
#   as before.
#
#   DISCLOSURE. When the block IS emitted it may carry EXACTLY the opaque ref —
#   never the email, custid, objid or extid, and never a second key. The extid
#   matters twice over here: it is the ref's PRE-IMAGE
#   (docs/specs/diagnostics/actor-ref-preimage-debate-decision.md), so emitting
#   it alongside the ref would hand the browser both input and output. The
#   frontend contract (diagnosticsRefSchema — not the unrelated
#   diagnosticsSchema, which is the Sentry config block) is a Zod strictObject
#   and is the one schema parsed against live data, so an extra key here makes
#   the client drop the whole block. A pseudonymous ORGANIZATION ref does exist
#   (DiagnosticsRef.organization_ref, on the colonel organization-detail record)
#   but is per-RESOURCE, not per-session, and must stay off this block.
#
#   RENDER SAFETY. This serializer is registered on all three web shells, so it
#   runs on EVERY authenticated render. Familia derives an extid lazily and
#   raises when the objid is absent or of unknown provenance, so an unreadable
#   extid must degrade to an omitted block, never to an exception — an
#   exception here is a 500 page plus a self-inflicted Sentry event.
#
# The serializer's declared output_template still lists `diagnostics_ref`, because
# SerializerRegistry strips any key a serializer did not declare — omission is
# achieved by not setting the key, not by leaving it undeclared.
#
# No Redis or SQL required.
#
# Run with:
#   tests/lanes/run unit --only apps/web/core/spec/views/serializers/diagnostics_serializer_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views'

RSpec.describe Core::Views::DiagnosticsSerializer do
  subject(:output) { described_class.serialize(view_vars) }

  let(:email) { 'operator@example.com' }
  let(:objid) { '01JORGABCDEFGHJKMNPQRSTVWX' }
  let(:org_extid) { 'on1234567890s' }
  let(:custid) { 'cust-1234567890' }

  # Shaped like a real Customer extid: Familia's external_identifier feature
  # under `format: 'ur%{id}'` emits `ur` plus 25 base36 characters.
  let(:cust_extid) { 'ur00fedcba9876543210zyxwvu' }
  let(:cust_objid) { '01JCUSTABCDEFGHJKMNPQRSTVW' }

  let(:colonel) { false }

  let(:cust) do
    instance_double(
      Onetime::Customer,
      email: email,
      custid: custid,
      objid: cust_objid,
      extid: cust_extid,
    ).tap { |double| allow(double).to receive(:role?).with(:colonel).and_return(colonel) }
  end

  let(:org) { Struct.new(:objid, :extid).new(objid, org_extid) }

  let(:view_vars) do
    { 'authenticated' => true, 'cust' => cust, 'organization' => org }
  end

  # Force a known keying state per context rather than inheriting whatever the
  # lane happens to export (tests/lanes/base.env sets ACCOUNT_ID_SECRET).
  def stub_keying(secret)
    allow(Onetime::Utils::DiagnosticsRef).to receive(:keying).and_return(secret)
  end

  context 'when the visitor is anonymous' do
    let(:view_vars) { { 'authenticated' => false, 'cust' => nil } }

    before { stub_keying('a-known-diagnostics-key') }

    it 'omits the diagnostics_ref key entirely' do
      expect(output).not_to have_key('diagnostics_ref')
    end

    it 'emits nothing at all rather than a null placeholder' do
      expect(output).to eq({})
    end
  end

  context 'when a customer object exists but the session is not authenticated' do
    let(:view_vars) { { 'authenticated' => false, 'cust' => cust } }

    before { stub_keying('a-known-diagnostics-key') }

    it 'omits the diagnostics_ref key' do
      expect(output).not_to have_key('diagnostics_ref')
    end
  end

  # Today `authenticated` is already false during the MFA-pending window, so
  # this exercises the explicit local guard: even if AuthenticationSerializer
  # ever reported authenticated=true mid-MFA, the ref must stay omitted.
  context 'when the session is awaiting MFA' do
    let(:view_vars) do
      { 'authenticated' => true, 'awaiting_mfa' => true, 'cust' => cust }
    end

    before { stub_keying('a-known-diagnostics-key') }

    it 'omits the diagnostics_ref key' do
      expect(output).not_to have_key('diagnostics_ref')
    end
  end

  context 'when ACCOUNT_ID_SECRET is not configured' do
    before { stub_keying(nil) }

    it 'omits the diagnostics_ref key for an authenticated user' do
      expect(output).not_to have_key('diagnostics_ref')
    end

    it 'does not raise, so the page still renders' do
      expect { output }.not_to raise_error
    end
  end

  # ACCOUNT_ID_SECRET is now the ONLY keying. FEDERATION_SECRET was dropped from
  # diagnostics entirely, and with it the residency apparatus and the scope
  # label: an extid is minted per install, so refs are per-install by
  # construction rather than by configuration.
  context 'when ACCOUNT_ID_SECRET keys the ref' do
    before { stub_keying('a-known-diagnostics-key') }

    it 'emits an opaque ref' do
      expect(output['diagnostics_ref']['actor_ref']).to match(/\A[0-9a-f]{16}\z/)
    end

    it 'matches the reference the module derives for that customer extid' do
      expect(output['diagnostics_ref']['actor_ref'])
        .to eq(Onetime::Utils::DiagnosticsRef.actor_ref(cust_extid))
    end

    it 'does NOT derive from the email' do
      expect(output['diagnostics_ref']['actor_ref'])
        .not_to eq(Onetime::Utils::DiagnosticsRef.actor_ref(email))
    end

    it 'gives two installs different refs for the same customer' do
      stub_keying('install-a')
      region_a = described_class.serialize(view_vars)['diagnostics_ref']['actor_ref']

      stub_keying('install-b')
      region_b = described_class.serialize(view_vars)['diagnostics_ref']['actor_ref']

      expect(region_a).not_to eq(region_b)
    end
  end

  # Familia derives an extid lazily from the objid and raises
  # ExternalIdentifierError when it cannot. This serializer runs on every
  # authenticated render, so that must cost the ref and nothing else.
  context 'when the customer extid is unreadable' do
    before { stub_keying('a-known-diagnostics-key') }

    context 'because it is nil' do
      let(:cust_extid) { nil }

      it 'omits the block instead of substituting another identifier' do
        expect(output).not_to have_key('diagnostics_ref')
      end
    end

    context 'because reading it raises' do
      let(:cust) do
        instance_double(Onetime::Customer).tap do |double|
          allow(double).to receive(:extid).and_raise(StandardError, 'missing objid field')
        end
      end

      it 'omits the block instead of raising out of the render' do
        expect { output }.not_to raise_error
        expect(output).not_to have_key('diagnostics_ref')
      end
    end
  end

  describe 'disclosure' do
    before { stub_keying('a-known-diagnostics-key') }

    let(:colonel) { true } # even a colonel gets only the one-key block here

    it 'leaks no identifier anywhere in the emitted payload' do
      serialized = output.to_json

      # cust_extid is in this list because it is the ref's PRE-IMAGE. Emitting
      # it beside the ref would give the browser the input and the output.
      [email, custid, objid, org_extid, cust_extid, cust_objid].each do |secret|
        expect(serialized).not_to include(secret)
      end
      expect(serialized).not_to include('@')
    end

    it 'carries exactly the one key the strict frontend schema accepts' do
      # A second key fails diagnosticsRefSchema (z.strictObject) and the client
      # discards the whole block — so widening this is a silent regression.
      expect(output['diagnostics_ref'].keys).to contain_exactly('actor_ref')
    end

    it 'no longer carries the actor_scope label' do
      # There is one keying now, so the label was constant. It was dropped from
      # the wire contract rather than pinned to a constant value; the frontend
      # schema is a strictObject, so re-adding it here would break the parse.
      expect(output['diagnostics_ref']).not_to have_key('actor_scope')
    end

    # A pseudonymous organization ref DOES exist (DiagnosticsRef.organization_ref,
    # published on the colonel organization-detail record). It must not appear
    # here. This block is per-SESSION and the org ref is per-RESOURCE: a session
    # touches many organizations, so any value pinned here would be tagged onto
    # later events about other orgs. And mechanically it is a second key in a
    # strictObject — the client would drop actor_ref with it.
    it 'stays a one-key per-session block even though org refs now exist' do
      expect(Onetime::Utils::DiagnosticsRef).to respond_to(:organization_ref)

      expect(output['diagnostics_ref'].keys).to contain_exactly('actor_ref')
      expect(output['diagnostics_ref']).not_to have_key('organization_ref')
    end

    it 'never emits the ref for the organization in scope on this render' do
      # `organization` is present in view_vars, so the serializer had the input
      # to derive one and declines to. Derived here under the SAME stubbed
      # keying to prove the value is genuinely derivable and genuinely absent,
      # rather than absent because the derivation happened to decline.
      org_ref = Onetime::Utils::DiagnosticsRef.organization_ref(org.objid)

      expect(org_ref).to match(/\A[0-9a-f]{16}\z/)
      expect(output.to_json).not_to include(org_ref)
    end

    it 'distinguishes one customer from another' do
      other = instance_double(
        Onetime::Customer,
        email: 'someone-else@example.com',
        custid: 'cust-9999999999',
        objid: '01JOTHERABCDEFGHJKMNPQRST',
        extid: 'ur00abcdef0123456789vwxyzu',
      ).tap { |double| allow(double).to receive(:role?).with(:colonel).and_return(false) }

      other_output = described_class.serialize(view_vars.merge('cust' => other))

      expect(other_output['diagnostics_ref']['actor_ref'])
        .not_to eq(output['diagnostics_ref']['actor_ref'])
    end
  end

  describe 'output_template' do
    it 'declares diagnostics_ref so SerializerRegistry does not strip it' do
      expect(described_class.output_template).to have_key('diagnostics_ref')
    end
  end

  describe 'registration' do
    it 'is registered with the serializer registry' do
      expect(Core::Views::SerializerRegistry.serializers).to include(described_class)
    end

    it 'is wired into every shell that renders the bootstrap payload' do
      [Core::Views::VuePoint, Core::Views::AdminPoint, Core::Views::BootstrapMe].each do |shell|
        expect(shell.serializers).to include(described_class),
          "Expected #{shell} to include DiagnosticsSerializer"
      end
    end
  end
end
