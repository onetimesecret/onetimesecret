# frozen_string_literal: true

require_relative '../integration_spec_helper'

RSpec.describe 'Organization sharing controls on mounted creation routes', type: :integration do
  include_context 'auth_rack_test'

  let(:customer) do
    Onetime::Customer.new(email: "sharing-#{SecureRandom.hex(6)}@example.com").tap do |account|
      account.update_passphrase('Sharing-Controls1234!')
      account.verified = 'true'
      account.apitoken = SecureRandom.hex(20)
      account.save
    end
  end
  let(:workspace) { Onetime::Organization.create!("Sharing #{SecureRandom.hex(6)}", customer) }
  let(:other) { Onetime::Organization.create!("Other #{SecureRandom.hex(6)}", customer) }
  let(:allowed) { %w[first@example.com second@listed.example.com] }
  let(:queued) { [] }

  before(:all) { Onetime.boot! :test }
  before do
    clear_cookies
    header 'Authorization', nil
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |template, data, **|
      queued << data.fetch(:recipient) if template == :secret_link
      true
    end
  end

  def set_policy(org, **values)
    org.replace_sharing_policy!(Onetime::Organization::SharingPolicy::DEFAULT.merge(values.transform_keys(&:to_s)))
  end

  def create(version, action, payload, guest: false)
    if version == 1
      path = action == 'conceal' ? 'share' : 'generate'
      post "/api/v1/#{path}", payload, { 'HTTP_ACCEPT' => 'application/json' }
    else
      post_json "/api/v#{version}/#{'guest/' if guest}secret/#{action}", { secret: payload }
    end
  end

  def expect_stored(version, expected)
    expect(last_response.status).to eq(200), last_response.body
    id = version == 1 ? json_response.fetch('metadata_key') : json_response.dig('record', 'receipt', 'identifier')
    receipt = Onetime::Receipt.load(id)
    expect(receipt.secret_ttl.to_i).to eq(expected)
    expect(Familia.dbclient.ttl(receipt.load_secret.dbkey)).to be_between(expected - 2, expected)
    wire_ttl = version == 1 ? json_response.fetch('secret_ttl') : json_response.dig('record', 'receipt', 'secret_ttl')
    expect(wire_ttl.to_i).to be_between(expected - 2, expected)
    receipt
  end

  around(:each, :custom_host) do |example|
    app
    original_config = OT.conf.get('features.domains')
    original_features = Onetime::Runtime.features
    begin
      OT.conf.get('features')['domains'] = original_config.merge('enabled' => true, 'default' => 'canonical.example.com')
      Onetime::Runtime.features = original_features.with(domains_enabled: true)
      Onetime::Middleware::DomainStrategy.initialize_from_config
      example.run
    ensure
      OT.conf.get('features')['domains'] = original_config
      Onetime::Runtime.features = original_features
      Onetime::Middleware::DomainStrategy.initialize_from_config
    end
  end

  it 'returns a v1 entitlement denial in the legacy error envelope without creating a secret' do
    basic_authorize customer.email, customer.apitoken
    header 'O-Organization-ID', workspace.objid
    allow_any_instance_of(Onetime::Organization).to receive(:limit_for).with('secret_lifetime').and_return(2_592_000)
    allow_any_instance_of(Onetime::Organization).to receive(:can?).with('extended_default_expiration').and_return(false)

    expect { create(1, 'conceal', { secret: 'extended lifetime', ttl: 2_592_000 }) }
      .not_to change { Onetime::Secret.instances.size }
    expect(last_response.status).to eq(404), last_response.body
    expect(last_response.headers['X-OTS-Intended-Status']).to eq('403')
    expect(json_response.keys).to eq(['message'])
    expect(json_response.fetch('message')).to include('extended default expiration')
  end

  def serve_domain(org)
    domain = Onetime::CustomDomain.new(display_domain: "sharing-#{SecureRandom.hex(6)}.tenant-example.com", org_id: org.objid)
    domain.ownership_verified = true
    domain.verified_by_override = true
    domain.verified = true
    domain.save
    Onetime::CustomDomain.display_domain_index.put(domain.display_domain, domain.identifier)
    org.domains.add(domain.objid)
    Onetime::CustomDomain::HomepageConfig.create!(domain_id: domain.identifier, enabled: true, secrets_mode: 'classic')
    Onetime::CustomDomain::ApiConfig.create!(domain_id: domain.identifier, enabled: true)
    domain
  end

  [1, 2, 3].each do |version|
    it "permits only the assigned custom domain for a v#{version} scoped member", :custom_host do
      owner = Onetime::Customer.create!(email: "sharing-owner-#{SecureRandom.hex(6)}@example.com")
      org = Onetime::Organization.create!("Scoped sharing #{SecureRandom.hex(6)}", owner)
      assigned = serve_domain(org)
      sibling = serve_domain(org)
      org.add_members_instance(customer, through_attrs: { role: 'member', status: 'active', domain_scope_id: assigned.objid })
         .materialize_for_role!
      header 'Host', 'canonical.example.com'
      if version == 3
        post_json '/auth/login', { login: customer.email, password: 'Sharing-Controls1234!' }
        expect(last_response.status).to eq(200), last_response.body
      else
        basic_authorize customer.email, customer.apitoken
      end
      header 'O-Organization-ID', org.objid
      data = { secret: 'domain-scoped creation', ttl: 300 }

      create(version, 'conceal', data.merge(share_domain: assigned.display_domain))
      expect_stored(version, 300)
      expect { create(version, 'conceal', data.merge(share_domain: sibling.display_domain)) }
        .not_to change { Onetime::Secret.instances.size }
      expect(last_response.status).to eq(version == 1 ? 404 : 403), last_response.body
    end
  end

  it 'preserves verified legacy sorted-set membership when selecting a domain on canonical', :custom_host do
    owner = Onetime::Customer.create!(email: "legacy-owner-#{SecureRandom.hex(6)}@example.com")
    legacy_org = Onetime::Organization.create!("Legacy sharing #{SecureRandom.hex(6)}", owner)
    domain = serve_domain(legacy_org)
    legacy_org.members.add(customer, Familia.now.to_f)
    expect(legacy_org.member?(customer)).to be(true)
    expect(Onetime::OrganizationMembership.find_by_org_customer(legacy_org.objid, customer.objid)).to be_nil

    basic_authorize customer.email, customer.apitoken
    header 'Host', 'canonical.example.com'
    header 'O-Organization-ID', workspace.objid
    create(2, 'conceal', { secret: 'legacy member', ttl: 300, share_domain: domain.display_domain })
    expect_stored(2, 300)

    # An error reading the through-record is distinct from its confirmed absence.
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer).and_call_original
    allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
      .with(legacy_org.objid, customer.objid).and_raise(IOError, 'membership read unavailable')
    expect { create(2, 'conceal', { secret: 'failed read', share_domain: domain.display_domain }) }
      .not_to change { Onetime::Secret.instances.size }
    expect(last_response.status).to be >= 400
  end

  it 'checks the selected domain scope when a separate loaded record represents the request host', :custom_host do
    owner = Onetime::Customer.create!(email: "scoped-owner-#{SecureRandom.hex(6)}@example.com")
    org = Onetime::Organization.create!("Scoped host #{SecureRandom.hex(6)}", owner)
    domain = serve_domain(org)
    sibling = serve_domain(org)
    # The selector and middleware can load different Ruby instances of the
    # same stored record (for example, alternate host spellings).
    selected = Onetime::CustomDomain.load(domain.objid)
    expect(selected.objid).to eq(domain.objid)
    expect(selected).not_to equal(domain)
    org.add_members_instance(customer, through_attrs: { role: 'member', status: 'active', domain_scope_id: sibling.objid })
       .materialize_for_role!
    lookup = Onetime::CustomDomain::Lookup.found(domain.display_domain, domain)
    strategy = double('Strategy', session: {}, user: customer, auth_method: 'basicauth', metadata: {
      organization_context: { organization: org }, domain_strategy: :custom,
      display_domain: domain.display_domain, custom_domain_lookup: lookup,
    })
    logic = V2::Logic::Secrets::ConcealSecret.new(strategy, { 'secret' => { 'secret' => 'scope validation' } })
    allow(logic).to receive(:sharing_domain_record).with(domain.display_domain).and_return(selected)
    expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden, /permission to use domain/)
  end

  it 'combines a custom host owner and a separately selected receipt workspace', :custom_host do
    host_domain = serve_domain(workspace)
    set_policy(workspace, passphrase_required: true, max_ttl: 604_800)
    set_policy(other, max_ttl: 300, recipient_email_mode: 'disabled')
    basic_authorize customer.email, customer.apitoken
    header 'Host', host_domain.display_domain
    header 'O-Organization-ID', other.objid

    create(2, 'conceal', { secret: 'host policy' })
    expect(last_request.env['onetime.domain_strategy']).to eq(:custom)
    expect(last_response.status).to eq(422), last_response.body
    create(2, 'conceal', { secret: 'receipt policy', passphrase: 'valid-passphrase', recipient: 'person@example.com' })
    expect(last_response.status).to eq(422), last_response.body
    create(2, 'conceal', { secret: 'both policies', passphrase: 'valid-passphrase', ttl: 600 })
    expect_stored(2, 300)
    expect(Onetime::Receipt.load(json_response.dig('record', 'receipt', 'identifier')).org_id).to eq(other.objid)
  end

  [1, 2, 3].each do |version|
    it "uses the saved domain passphrase and the owner's lifetime for a v#{version} guest", :custom_host do
      host_domain = serve_domain(workspace)
      host_domain.brand.put('passphrase_required', 'true')
      set_policy(workspace, max_ttl: 120)
      header 'Host', host_domain.display_domain
      %w[conceal generate].each do |action|
        create(version, action, { secret: 'guest secret' }, guest: true)
        expect(last_request.env['onetime.domain_strategy']).to eq(:custom)
        expect(last_response.status).to eq(version == 1 ? 404 : 422), last_response.body
        create(version, action, { secret: 'guest secret', passphrase: 'valid-passphrase' }, guest: true)
        expect_stored(version, 120)
      end
    end
  end

  [1, 2, 3].each do |version|
    %w[conceal generate].each do |action|
      it "enforces the selected workspace for v#{version} #{action} and sends only to the first recipient" do
        set_policy(workspace, recipient_email_mode: 'restricted', recipient_email_domains: %w[example.com listed.example.com],
          passphrase_required: true, max_ttl: 604_800)
        set_policy(other, recipient_email_mode: 'disabled', max_ttl: 60)
        if version == 3
          post_json '/auth/login', { login: customer.email, password: 'Sharing-Controls1234!' }
          expect(last_response.status).to eq(200), last_response.body
        else
          basic_authorize customer.email, customer.apitoken
        end
        header 'O-Organization-ID', workspace.objid
        data = { secret: 'shared value', passphrase: 'secret-passphrase', recipient: allowed }
        error_status = version == 1 ? 404 : 422

        outside = 'outside@unlisted.example.com'
        [
          data.merge(recipient: [outside, allowed.first]),
          data.merge(recipient: ['invalid-address', allowed.first]),
          data.merge(passphrase: " \t "),
        ].each do |bad|
          expect { create(version, action, bad) }.not_to change { Onetime::Secret.instances.size }
          expect(last_response.status).to eq(error_status), last_response.body
          expect(queued).to be_empty
        end

        # A legacy array contributes only its first sanitized address. Later
        # entries are neither validated, recorded nor sent the link.
        [[allowed.last, outside], [allowed.last, 'invalid-address']].each do |list|
          create(version, action, data.merge(recipient: list, ttl: 300))
          receipt = expect_stored(version, 300)
          expect(receipt.recipients).to eq(OT::Utils.obscure_email(allowed.last))
          expect(queued).to eq([allowed.last])
          queued.clear
        end

        [59, 60, 604_799, 604_800, 604_801].each do |ttl|
          create(version, action, data.merge(ttl: ttl))
          receipt = expect_stored(version, ttl.clamp(60, 604_800))
          expect(receipt.recipients).to eq(OT::Utils.obscure_email(allowed.first))
          expect(queued).to eq([allowed.first])
          queued.clear
        end

        header 'O-Organization-ID', other.objid
        expect { create(version, action, data) }.not_to change { Onetime::Secret.instances.size }
        expect(last_response.status).to eq(error_status), last_response.body
        expect(queued).to be_empty
        create(version, action, { secret: 'different workspace' })
        expect_stored(version, 60)
      end
    end
  end

  describe 'recipient domain matching on v1, v2 and v3' do
    let(:policy_refusal) { /Recipient email is restricted by the organization/ }
    let(:undeliverable) { /Undeliverable email address/ }

    def sign_in(version)
      if version == 3
        post_json '/auth/login', { login: customer.email, password: 'Sharing-Controls1234!' }
        expect(last_response.status).to eq(200), last_response.body
      else
        basic_authorize customer.email, customer.apitoken
      end
      header 'O-Organization-ID', workspace.objid
    end

    # Each row is [recipient payload, outcome]. An outcome String is the one
    # address expected to be recorded and mailed; a Regexp is the expected
    # refusal message, which tells the policy check from the address check.
    def expect_rows(version, action, rows)
      rows.each do |recipient, outcome|
        label = "v#{version} #{action} recipient=#{recipient.inspect}"
        if outcome.is_a?(Regexp)
          expect { create(version, action, { secret: 'v', ttl: 300, recipient: recipient }) }
            .not_to change { Onetime::Secret.instances.size }
          expect(last_response.status).to eq(version == 1 ? 404 : 422), "#{label}: #{last_response.body}"
          # v1 keeps the legacy {message} envelope; v2/v3 name the field.
          message = version == 1 ? json_response.fetch('message') : json_response.fetch('error')
          expect(message).to match(outcome), "#{label}: #{last_response.body}"
          expect(json_response['field']).to eq('recipient'), "#{label}: #{last_response.body}" unless version == 1
          expect(queued).to be_empty, label
        else
          create(version, action, { secret: 'v', ttl: 300, recipient: recipient })
          receipt = expect_stored(version, 300)
          expect(receipt.recipients).to eq(OT::Utils.obscure_email(outcome)), label
          expect(queued).to eq([outcome]), label
        end
        queued.clear
      end
    end

    [1, 2, 3].each do |version|
      it "skips an entry that sanitizes to empty before choosing the first recipient for v#{version}" do
        set_policy(workspace, recipient_email_mode: 'restricted', recipient_email_domains: ['example.com'])
        sign_in(version)
        rows = [
          [['  ', 'user@example.com'], 'user@example.com'],
          [['<b></b>', 'user@example.com'], 'user@example.com'],
        ]
        expect_rows(version, 'conceal', rows)
      end

      %w[conceal generate].each do |action|
        it "matches the listed domains exactly for v#{version} #{action}" do
          set_policy(workspace, recipient_email_mode: 'restricted', recipient_email_domains: ['Example.COM', 'bücher.example'])
          expect(workspace.sharing_policy['recipient_email_domains']).to eq(%w[example.com xn--bcher-kva.example])
          sign_in(version)

          rows = [
            # Exact match, with case and surrounding space normalized away.
            ['user@example.com', 'user@example.com'],
            ['USER@Example.COM', 'user@example.com'],
            [' user@example.com ', 'user@example.com'],
            # The Unicode and A-label spellings match the one stored key; the
            # address is mailed as written.
            ['user@bücher.example', 'user@bücher.example'],
            ['user@BÜCHER.example', 'user@bücher.example'],
            ['user@xn--bcher-kva.example', 'user@xn--bcher-kva.example'],
            # Single recipient: the first non-empty entry is the only one
            # checked, recorded and mailed.
            [['user@example.com', 'outside@eng.example.com'], 'user@example.com'],
            [['user@example.com', 'not-an-email'], 'user@example.com'],
            [['', 'user@example.com', 'outside@unlisted.test'], 'user@example.com'],
            [['outside@eng.example.com', 'user@example.com'], policy_refusal],
            [['not-an-email', 'user@example.com'], policy_refusal],
            # A subdomain of a listed domain is not listed.
            ['user@eng.example.com', policy_refusal],
            ['user@mail.bücher.example', policy_refusal],
            ['user@notexample.com', policy_refusal],
            # The address keeps its trailing dot, so "example.com." is not
            # the listed "example.com".
            ['user@example.com.', policy_refusal],
            ['userexample.com', policy_refusal],
            ['user@', policy_refusal],
            ['user@-bad.example.com', policy_refusal],
            ['user@ex ample.com', policy_refusal],
            # The policy itself refuses anything but a single bare address,
            # without relying on the deliverability check that follows.
            ['a@b@example.com', policy_refusal],
            ['@example.com', policy_refusal],
            ['user@evil.test,other@example.com', policy_refusal],
          ]
          expect_rows(version, action, rows)
        end

        it "allows a listed subdomain without its parent for v#{version} #{action}" do
          set_policy(workspace, recipient_email_mode: 'restricted', recipient_email_domains: ['eng.example.com'])
          sign_in(version)

          rows = [
            ['user@eng.example.com', 'user@eng.example.com'],
            ['user@example.com', policy_refusal],
            ['user@ops.example.com', policy_refusal],
          ]
          expect_rows(version, action, rows)
        end

        it "refuses every address when disabled and allows any valid one when unrestricted for v#{version} #{action}" do
          set_policy(workspace, recipient_email_mode: 'disabled')
          sign_in(version)
          rows = [
            ['user@example.com', policy_refusal],
            [['user@example.com'], policy_refusal],
          ]
          expect_rows(version, action, rows)
          create(version, action, { secret: 'no recipient', ttl: 300 })
          expect_stored(version, 300)

          set_policy(workspace, recipient_email_mode: 'unrestricted')
          rows = [
            ['user@unlisted.test', 'user@unlisted.test'],
            ['user@eng.example.com', 'user@eng.example.com'],
            [['user@unlisted.test', 'second@example.com'], 'user@unlisted.test'],
            ['not-an-email', undeliverable],
            ['a@b@example.com', undeliverable],
          ]
          expect_rows(version, action, rows)
        end
      end
    end
  end

  describe 'with an unreadable stored policy' do
    ['{not json', JSON.generate('recipient_email_mode' => 'sometimes'), JSON.generate([1, 2])].each do |stored|
      it "enforces the strictest policy and keeps the organization readable: #{stored[0, 24]}" do
        workspace.sharing_policy_json.value = stored
        allow(OT).to receive(:le).and_call_original

        expect(workspace.sharing_policy).to eq(Onetime::Organization::SharingPolicy::STRICTEST)
        expect(workspace.sharing_policy_invalid?).to be(true)
        dumped = workspace.safe_dump
        expect(dumped[:sharing_policy]).to eq(Onetime::Organization::SharingPolicy::STRICTEST)
        expect(dumped[:sharing_policy_invalid]).to be(true)
        serialized = Core::Views::OrganizationSerializer.serialize(
          'authenticated' => true, 'organization' => workspace, 'cust' => customer,
        ).fetch('organization')
        expect(serialized).to include('sharing_policy_invalid' => true)
        expect(OT).to have_received(:le).with(/Stored sharing policy is invalid/, hash_including(org_id: workspace.objid)).at_least(:once)

        basic_authorize customer.email, customer.apitoken
        header 'O-Organization-ID', workspace.objid
        [{ secret: 'v', passphrase: 'secret-passphrase', recipient: allowed.first }, { secret: 'v' }].each do |bad|
          expect { create(2, 'conceal', bad) }.not_to change { Onetime::Secret.instances.size }
          expect(last_response.status).to eq(422), last_response.body
        end
        expect(queued).to be_empty

        create(2, 'conceal', { secret: 'v', passphrase: 'secret-passphrase', ttl: 604_800 })
        expect_stored(2, 60)

        set_policy(workspace)
        expect(workspace.sharing_policy_invalid?).to be(false)
        expect(workspace.sharing_policy).to eq(Onetime::Organization::SharingPolicy::DEFAULT)
      end
    end
  end
end
