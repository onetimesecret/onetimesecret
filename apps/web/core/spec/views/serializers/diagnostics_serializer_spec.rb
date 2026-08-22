# apps/web/core/spec/views/serializers/diagnostics_serializer_spec.rb
#
# frozen_string_literal: true

# Coverage for DiagnosticsSerializer's pseudonymous user reference.
#
# The bootstrap payload is the only channel that hands the browser Sentry SDK
# an reference, so this file pins the two directions that can go wrong:
#
#   OMISSION. Anonymous visitors, awaiting-MFA sessions, and installs with
#   neither FEDERATION_SECRET nor ACCOUNT_ID_SECRET must produce NO `diagnostics_ref`
#   key at all. Absence is the contract — not a null, not an empty string —
#   because an anonymous visitor has no reference to report and an unconfigured
#   install (the default in dev and test) must render exactly as before.
#
#   DISCLOSURE. When the block IS emitted it may carry EXACTLY the opaque ref
#   and its scope label — never the email, custid, objid or extid, and never a
#   third key. The frontend contract (diagnosticsRefSchema — not the unrelated
#   diagnosticsSchema, which is the Sentry config block) is a Zod strictObject
#   and is the one schema parsed against live data, so an extra key here makes
#   the client drop the whole block. A pseudonymous ORGANIZATION ref does exist
#   (DiagnosticsRef.organization_ref, on the colonel organization-detail record)
#   but is per-RESOURCE, not per-session, and must stay off this block.
#
#   RENDER SAFETY. This serializer is registered on all three web shells, so it
#   runs on EVERY authenticated render. A stored email that is not valid UTF-8
#   must therefore degrade to an omitted block, never to an exception — an
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
  let(:extid) { 'on1234567890s' }
  let(:custid) { 'cust-1234567890' }

  let(:colonel) { false }

  let(:cust) do
    instance_double(
      Onetime::Customer,
      email: email,
      custid: custid,
      objid: '01JCUSTABCDEFGHJKMNPQRSTVW',
      extid: 'ur1234567890s',
    ).tap { |double| allow(double).to receive(:role?).with(:colonel).and_return(colonel) }
  end

  let(:org) { Struct.new(:objid, :extid).new(objid, extid) }

  let(:view_vars) do
    { 'authenticated' => true, 'cust' => cust, 'organization' => org }
  end

  # Set env vars for the duration of a block and restore them, including
  # deletion when the original was unset.
  def with_env(pairs)
    original = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end

  # Force a known keying state per context rather than inheriting whatever the
  # lane happens to export (tests/lanes/base.env sets both secrets).
  #
  # A federated keying MUST carry a residency: DiagnosticsRef refuses to derive a
  # ref from the shared federation secret with no residency resolved, so a stub
  # that omitted one would silently make every federated example emit nothing.
  def stub_keying(scope, residency: 'stub-region')
    if scope.nil?
      allow(Onetime::Utils::DiagnosticsRef).to receive(:keying).and_return(nil)
    else
      keying = Onetime::Utils::DiagnosticsRef::Keying.new(
        secret: 'a-known-diagnostics-key', scope: scope, residency: residency
      )
      allow(Onetime::Utils::DiagnosticsRef).to receive(:keying).and_return(keying)
    end
  end

  context 'when the visitor is anonymous' do
    let(:view_vars) { { 'authenticated' => false, 'cust' => nil } }

    before { stub_keying('federated') }

    it 'omits the diagnostics_ref key entirely' do
      expect(output).not_to have_key('diagnostics_ref')
    end

    it 'emits nothing at all rather than a null placeholder' do
      expect(output).to eq({})
    end
  end

  context 'when a customer object exists but the session is not authenticated' do
    let(:view_vars) { { 'authenticated' => false, 'cust' => cust } }

    before { stub_keying('federated') }

    it 'omits the diagnostics_ref key' do
      expect(output).not_to have_key('diagnostics_ref')
    end
  end

  context 'when neither secret is configured' do
    before { stub_keying(nil) }

    it 'omits the diagnostics_ref key for an authenticated user' do
      expect(output).not_to have_key('diagnostics_ref')
    end

    it 'does not raise, so the page still renders' do
      expect { output }.not_to raise_error
    end
  end

  context 'when FEDERATION_SECRET keys the ref' do
    before { stub_keying('federated') }

    it 'emits an opaque ref labelled federated' do
      expect(output['diagnostics_ref']['user_scope']).to eq('federated')
      expect(output['diagnostics_ref']['user_ref']).to match(/\A[0-9a-f]{16}\z/)
    end

    it 'matches the reference the module derives for that email' do
      expect(output['diagnostics_ref']['user_ref'])
        .to eq(Onetime::Utils::DiagnosticsRef.user_ref(email))
    end
  end

  context 'when only ACCOUNT_ID_SECRET keys the ref' do
    before { stub_keying('deployment', residency: nil) }

    it 'emits an opaque ref labelled deployment' do
      expect(output['diagnostics_ref']['user_scope']).to eq('deployment')
      expect(output['diagnostics_ref']['user_ref']).to match(/\A[0-9a-f]{16}\z/)
    end
  end

  # The keying decision is exercised end to end here — no stub_keying — because
  # the defect being pinned was that the SAFE state required configuration.
  # A shared FEDERATION_SECRET plus an operator who declared nothing must not
  # produce a federated, cross-region-correlatable reference in the payload.
  context 'when FEDERATION_SECRET is set but no residency scope is declared' do
    before { allow(OT).to receive(:conf).and_return({}) }

    it 'narrows the emitted label to deployment rather than claiming federated' do
      with_env('FEDERATION_SECRET' => 'shared-across-regional-instances',
               'DIAGNOSTICS_REF_REGION' => nil,
               'ACCOUNT_ID_SECRET' => 'per-install-only') do
        expect(output['diagnostics_ref']['user_scope']).to eq('deployment')
      end
    end

    it 'omits the block entirely when there is no per-deployment secret to fall back to' do
      with_env('FEDERATION_SECRET' => 'shared-across-regional-instances',
               'DIAGNOSTICS_REF_REGION' => nil,
               'ACCOUNT_ID_SECRET' => nil) do
        expect(output).not_to have_key('diagnostics_ref')
      end
    end

    it 'gives two installs sharing the secret different refs for the same person' do
      shared = 'shared-across-regional-instances'
      env    = { 'FEDERATION_SECRET' => shared, 'DIAGNOSTICS_REF_REGION' => nil }

      region_a = with_env(env.merge('ACCOUNT_ID_SECRET' => 'install-a')) { output['diagnostics_ref'] }
      region_b = with_env(env.merge('ACCOUNT_ID_SECRET' => 'install-b')) do
        described_class.serialize(view_vars)['diagnostics_ref']
      end

      expect(region_a['user_ref']).not_to eq(region_b['user_ref'])
    end

    it 'restores federated keying once a residency scope is declared' do
      with_env('FEDERATION_SECRET' => 'shared-across-regional-instances',
               'DIAGNOSTICS_REF_REGION' => 'eu') do
        expect(output['diagnostics_ref']['user_scope']).to eq('federated')
      end
    end
  end

  # A residency read that blows up must cost this render its reference, not hand
  # it a DIFFERENT one — a second ref for the same human forks one Sentry user
  # in two and destroys "is this one user or fifty?".
  context 'when the residency config read fails transiently' do
    # Swapped inline rather than via `allow`, because a raising OT.conf would
    # still be installed when spec_helper's after hook reads it during teardown.
    def with_failing_conf
      original = OT.method(:conf)
      OT.define_singleton_method(:conf) { raise 'transient config failure' }
      yield
    ensure
      OT.define_singleton_method(:conf, original)
    end

    it 'omits the block instead of emitting a second reference for the same person' do
      with_env('FEDERATION_SECRET' => 'shared-across-regional-instances',
               'DIAGNOSTICS_REF_REGION' => nil,
               'ACCOUNT_ID_SECRET' => 'per-install-only') do
        with_failing_conf { expect(output).not_to have_key('diagnostics_ref') }
      end
    end

    it 'still renders rather than raising out of the view' do
      with_env('DIAGNOSTICS_REF_REGION' => nil) do
        with_failing_conf { expect { output }.not_to raise_error }
      end
    end
  end

  # A residency read that changes MID-DERIVATION is the sharper version of the
  # transient failure above: nothing raises, so the raise-based guard never
  # engages. The ref and the label the browser receives must still describe ONE
  # read of the config — before the fix the ref was keyed with the shared
  # federation secret over an 'unscoped' pre-image (identical on every install
  # sharing that secret) while the label read 'deployment'.
  context 'when the residency config changes mid-derivation' do
    let(:shared) { 'shared-across-regional-instances' }

    let(:env) do
      { 'FEDERATION_SECRET' => shared,
        'DIAGNOSTICS_REF_REGION' => nil,
        'ACCOUNT_ID_SECRET' => 'per-install-only' }
    end

    # OT.conf is swapped inline rather than via `allow` throughout this context,
    # because a conf installed by these helpers must be gone before
    # spec_helper's teardown reads it.
    def with_conf(conf)
      original = OT.method(:conf)
      OT.define_singleton_method(:conf) { conf }
      yield
    ensure
      OT.define_singleton_method(:conf, original)
    end

    def conf_object(&dig)
      Object.new.tap { |obj| obj.define_singleton_method(:dig, &dig) }
    end

    # Answers a healthy jurisdiction for the FIRST residency resolution, then
    # goes falsy. Triggered by the resolution itself rather than by counting
    # OT.conf reads, so it does not depend on the implementation's read count.
    def with_conf_falsy_after_first_resolution(jurisdiction)
      resolved = false
      conf     = conf_object do |*path|
        next nil unless path == %w[features regions current_jurisdiction]

        resolved = true
        jurisdiction
      end

      original = OT.method(:conf)
      OT.define_singleton_method(:conf) { resolved ? nil : conf }
      yield
    ensure
      OT.define_singleton_method(:conf, original)
    end

    # No nil anywhere: the declared jurisdiction simply drifts between
    # resolutions, as an operator edit or a config reload would make it.
    def with_drifting_jurisdiction(*sequence)
      queue = sequence.dup
      conf  = conf_object do |*path|
        next nil unless path == %w[features regions current_jurisdiction]

        queue.length > 1 ? queue.shift : queue.first
      end

      with_conf(conf) { yield }
    end

    def diagnostics_ref
      described_class.serialize(view_vars)['diagnostics_ref']
    end

    def healthy(jurisdiction)
      conf = { 'features' => { 'regions' => { 'current_jurisdiction' => jurisdiction } } }
      with_env(env) { with_conf(conf) { diagnostics_ref } }
    end

    def faulted(jurisdiction)
      with_env(env) { with_conf_falsy_after_first_resolution(jurisdiction) { diagnostics_ref } }
    end

    it 'emits the same reference during the window as outside it' do
      expect(faulted('eu')).to eq(healthy('eu'))
    end

    it 'does not collide two jurisdictions onto one ref' do
      expect(faulted('eu')['user_ref']).not_to eq(faulted('us')['user_ref'])
    end

    it 'does not invert the label downward over a federation-keyed ref' do
      expected = OpenSSL::HMAC.hexdigest(
        'SHA256', shared,
        [Onetime::Utils::DiagnosticsRef::USER_INFO, 'eu', email]
          .join(Onetime::Utils::DiagnosticsRef::SEPARATOR),
      )[0, Onetime::Utils::DiagnosticsRef::REF_LENGTH]

      expect(faulted('eu')['user_ref']).to eq(expected)
      expect(faulted('eu')['user_scope']).to eq('federated')
    end

    it 'keys on the read that chose the secret when the jurisdiction drifts' do
      drifted = with_env(env) { with_drifting_jurisdiction('eu', 'us') { diagnostics_ref } }

      expect(drifted).to eq(healthy('eu'))
      expect(drifted['user_ref']).not_to eq(healthy('us')['user_ref'])
    end
  end

  describe 'disclosure' do
    before { stub_keying('federated') }

    let(:colonel) { true } # even a colonel gets only the two-key block here

    it 'leaks no identifier anywhere in the emitted payload' do
      serialized = output.to_json

      [email, custid, objid, extid, 'ur1234567890s', '01JCUSTABCDEFGHJKMNPQRSTVW'].each do |secret|
        expect(serialized).not_to include(secret)
      end
      expect(serialized).not_to include('@')
    end

    it 'carries exactly the two keys the strict frontend schema accepts' do
      # A third key fails diagnosticsSchema (z.strictObject) and the client
      # discards the whole block — so widening this is a silent regression.
      expect(output['diagnostics_ref'].keys).to contain_exactly('user_ref', 'user_scope')
    end

    # A pseudonymous organization ref DOES exist (DiagnosticsRef.organization_ref,
    # published on the colonel organization-detail record). It must not appear
    # here. This block is per-SESSION and the org ref is per-RESOURCE: a session
    # touches many organizations, so any value pinned here would be tagged onto
    # later events about other orgs. And mechanically it is a third key in a
    # strictObject — the client would drop user_ref and user_scope with it.
    it 'stays a two-key per-session block even though org refs now exist' do
      expect(Onetime::Utils::DiagnosticsRef).to respond_to(:organization_ref)

      expect(output['diagnostics_ref'].keys).to contain_exactly('user_ref', 'user_scope')
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

    # user_scope is an ACCEPTED disclosure: it tells an authenticated browser
    # how this install is keyed. That is accepted because the frontend uses it
    # as the correlation-blast-radius tag on every Sentry event. It is accepted
    # ONLY while it describes the key — the moment it varies per account it is
    # account data on an anonymity surface.
    it 'is a property of the keying, not of the account' do
      other = instance_double(
        Onetime::Customer,
        email: 'someone-else@example.com',
        custid: 'cust-9999999999',
        objid: '01JOTHERABCDEFGHJKMNPQRST',
        extid: 'ur9999999999s',
      ).tap { |double| allow(double).to receive(:role?).with(:colonel).and_return(false) }

      other_output = described_class.serialize(view_vars.merge('cust' => other))

      expect(other_output['diagnostics_ref']['user_scope']).to eq(output['diagnostics_ref']['user_scope'])
      expect(other_output['diagnostics_ref']['user_ref']).not_to eq(output['diagnostics_ref']['user_ref'])
    end
  end

  # Emails reach us from the datastore, from SSO providers and from legacy
  # rows. String#unicode_normalize raises on anything that is not valid UTF-8,
  # and normalization sits on this render path.
  describe 'a stored email that is not valid UTF-8' do
    before { stub_keying('federated') }

    context 'with an invalid byte' do
      let(:email) { "a\xFF@b.com" }

      it 'omits the block instead of raising out of the render' do
        expect { output }.not_to raise_error
        expect(output).not_to have_key('diagnostics_ref')
      end
    end

    context 'with a truncated multibyte sequence' do
      let(:email) { "\xC3(@b.com" }

      it 'omits the block instead of raising out of the render' do
        expect { output }.not_to raise_error
        expect(output).not_to have_key('diagnostics_ref')
      end
    end

    context 'with correct UTF-8 bytes under a binary encoding tag' do
      let(:email) { 'operator@example.com'.dup.force_encoding(Encoding::ASCII_8BIT) }

      it 'still emits the same ref as the correctly tagged address' do
        expect(output['diagnostics_ref']['user_ref'])
          .to eq(Onetime::Utils::DiagnosticsRef.user_ref('operator@example.com'))
      end
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
