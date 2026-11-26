# spec/unit/onetime/models/secret_reveal_notice_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# The owner's reveal notice (secret_revealed) and the expiration timeline,
# at the model level.
#
# Every reveal path in every API version consumes a secret through
# Secret#consume_after_reveal! (via Secret#revealed! or Secret#reveal!), so
# the notice is sent there, once, and only when the receipt's own CAS reports
# this caller as the one that moved it to revealed. A reveal or burn also
# takes the receipt off Receipt.expiration_timeline, so the expiration
# warning job never warns about a secret that is gone.
#
# The per-route coverage (v1, v2, v3, ShowSecret continue=true) is in
# spec/integration/simple/reveal_notice_paths_spec.rb.
RSpec.describe Onetime::Secret, 'reveal notice and expiration timeline' do
  before(:all) { Onetime.boot! :test }

  # Above min_warning_ttl (48h), so spawn_pair puts the receipt on the
  # expiration timeline.
  let(:lifespan) { 3 * 24 * 3600 }

  let(:owner) do
    Onetime::Customer.new(email: "reveal-notice-#{SecureRandom.hex(8)}@example.com").tap do |cust|
      cust.notify_on_reveal = 'true'
      cust.locale           = 'fr'
      cust.save
    end
  end

  let(:sent) { [] }

  before do
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |template, data, **options|
      sent << [template, data, options]
      true
    end
  end

  let(:pairs) { [] }

  after do
    pairs.each do |receipt, secret|
      Onetime::Receipt.expiration_timeline.remove_element(receipt.identifier)
      secret.destroy! if secret.exists?
      receipt.destroy! if receipt.exists?
    end
    owner.destroy! if owner.exists?
  rescue StandardError => ex
    warn "[reveal-notice spec] cleanup failed: #{ex.class}"
  end

  def notices
    sent.select { |template, _data, _options| template == :secret_revealed }
  end

  def spawn(domain: nil, owner_id: owner.objid, **opts)
    Onetime::Receipt.spawn_pair(owner_id, lifespan, 'reveal notice fixture', domain: domain, **opts).tap do |pair|
      pairs << pair
    end
  end

  def on_timeline?(receipt)
    !Onetime::Receipt.expiration_timeline.score(receipt.identifier).nil?
  end

  describe 'one notice per reveal' do
    it 'sends one notice from Secret#revealed!' do
      _receipt, secret = spawn
      expect(secret.revealed!).to be(true)
      expect(notices.size).to eq(1)
    end

    it 'sends one notice from Secret#reveal!' do
      _receipt, secret = spawn
      expect(secret.reveal!).to eq('reveal notice fixture')
      expect(notices.size).to eq(1)
    end

    it 'sends the short id, the time and the locale, and no identifier' do
      receipt, secret = spawn
      secret.reveal!

      template, data, options = notices.first
      expect(template).to eq(:secret_revealed)
      expect(data.keys).to contain_exactly(:recipient, :secret_shortid, :revealed_at, :locale)
      expect(data).to include(recipient: owner.email, secret_shortid: secret.shortid, locale: 'fr')
      expect(Time.iso8601(data[:revealed_at])).to be_within(60).of(Time.now.utc)
      expect(options).to eq(domain_id: nil)
      expect(data.values.map(&:to_s)).not_to include(secret.identifier, receipt.identifier)
      expect(data.to_s).not_to include('reveal notice fixture')
    end

    it 'sends nothing to the race loser: two loaded instances, one notice' do
      _receipt, secret = spawn
      first  = Onetime::Secret.load(secret.identifier)
      second = Onetime::Secret.load(secret.identifier)

      results = [first.reveal!, second.reveal!]

      expect(results.compact.size).to eq(1)
      expect(notices.size).to eq(1)
    end

    # The secret CAS is won but the receipt CAS is not (the receipt already
    # moved): the notice is gated on the receipt's transition, so none goes.
    it 'sends nothing when the receipt transition is lost' do
      receipt, secret = spawn
      expect(Onetime::Receipt.load(receipt.identifier).revealed!).to be(true)

      expect(secret.reveal!).to eq('reveal notice fixture')
      expect(notices).to be_empty
    end
  end

  describe 'when no notice is due' do
    it 'sends nothing for an account verification secret (boolean flag and kind)' do
      _receipt, secret = spawn(expiration_notifications: false)
      secret.verification = true
      secret.kind         = 'account_verification'
      secret.save

      expect(Onetime::Secret.load(secret.identifier).reveal!).not_to be_nil
      expect(notices).to be_empty
    end

    it "sends nothing for a legacy verification secret stored as 'true' with no kind" do
      _receipt, secret = spawn
      secret.verification = 'true'
      secret.save

      expect(Onetime::Secret.load(secret.identifier).revealed!).to be(true)
      expect(notices).to be_empty
    end

    it "sends nothing for kind 'account_verification' with the verification flag unset" do
      _receipt, secret = spawn
      secret.kind = 'account_verification'
      secret.save
      fresh = Onetime::Secret.load(secret.identifier)
      expect(fresh.verification?).to be(false)

      expect(fresh.revealed!).to be(true)
      expect(notices).to be_empty
    end

    it 'sends nothing when the owner has not opted in' do
      owner.notify_on_reveal = 'false'
      owner.save
      _receipt, secret = spawn

      secret.reveal!
      expect(notices).to be_empty
    end

    it 'sends nothing for an anonymous secret' do
      _receipt, secret = spawn(owner_id: 'anon')

      secret.reveal!
      expect(notices).to be_empty
    end

    it 'sends nothing when the owner has no email' do
      owner.email = ''
      owner.save
      _receipt, secret = spawn

      secret.reveal!
      expect(notices).to be_empty
    end
  end

  describe 'locale and sender domain' do
    it 'falls back to the default locale when the owner locale is blank' do
      owner.locale = ''
      owner.save
      _receipt, secret = spawn

      secret.reveal!
      expect(notices.first[1][:locale]).to eq(OT.default_locale)
    end

    # Sender: the receipt's stored domain_id, only while that CustomDomain
    # still exists, carries the share domain, and belongs to the receipt's
    # organization (Receipt.sender_domain_id_for). Otherwise nil, the
    # default sender: a name that changed hands never sends from its new
    # holder.
    context 'sender domain' do
      let(:share_domain) { 'secrets.acme.example' }
      let(:stored) { { display_domain: share_domain, org_id: 'org-a' } }

      before do
        allow(Onetime::CustomDomain).to receive(:load).and_call_original
        allow(Onetime::CustomDomain).to receive(:load).with('cd-acme') do
          stored && instance_double(Onetime::CustomDomain, identifier: 'cd-acme', **stored)
        end
      end

      def reveal_from_domain(org_id: 'org-a')
        _receipt, secret = spawn(domain: share_domain, domain_id: 'cd-acme', org_id: org_id)
        secret.reveal!
        notices.first
      end

      it 'passes the stored domain_id when the domain still matches' do
        _template, data, options = reveal_from_domain
        expect(options).to eq(domain_id: 'cd-acme')
        expect(data).not_to include(:share_domain)
      end

      context 'when the domain no longer exists' do
        let(:stored) { nil }

        it 'falls back to the default sender' do
          expect(reveal_from_domain[2]).to eq(domain_id: nil)
        end
      end

      context 'when the record now carries another display domain' do
        let(:stored) { { display_domain: 'other.example', org_id: 'org-a' } }

        it 'falls back to the default sender' do
          expect(reveal_from_domain[2]).to eq(domain_id: nil)
        end
      end

      context 'when the record belongs to another organization' do
        let(:stored) { { display_domain: share_domain, org_id: 'org-b' } }

        it 'falls back to the default sender' do
          expect(reveal_from_domain[2]).to eq(domain_id: nil)
        end
      end

      it 'falls back to the default sender for a receipt without org_id (incoming)' do
        expect(reveal_from_domain(org_id: nil)[2]).to eq(domain_id: nil)
      end

      it 'gives the job the same answer through Receipt#sender_domain_id' do
        receipt, _secret = spawn(domain: share_domain, domain_id: 'cd-acme', org_id: 'org-a')
        expect(Onetime::Receipt.load(receipt.identifier).sender_domain_id).to eq('cd-acme')
      end
    end
  end

  describe 'a notification failure' do
    it 'does not fail the reveal' do
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_raise(StandardError, 'broker down')
      receipt, secret = spawn

      expect(secret.reveal!).to eq('reveal notice fixture')
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(:secret_revealed, anything, domain_id: nil)
      expect(Onetime::Secret.load(secret.identifier)).to be_nil
      expect(Onetime::Receipt.load(receipt.identifier).state).to eq('revealed')
    end

    it 'does not fail the reveal when the owner lookup raises' do
      allow(Onetime::Customer).to receive(:load).and_raise(Redis::CannotConnectError, 'down')
      _receipt, secret = spawn

      expect(secret.revealed!).to be(true)
      expect(Onetime::Customer).to have_received(:load).with(owner.objid)
      expect(Onetime::Secret.load(secret.identifier)).to be_nil
    end

    # T5: a read in the snapshot raises. The snapshot rescues, the reveal
    # completes and destroys the secret, and no notice is sent.
    it 'does not fail the reveal when the notice snapshot raises' do
      _receipt, secret = spawn
      allow(secret).to receive(:verification?).and_raise(Familia::Problem, 'bad field')

      expect(secret.reveal!).to eq('reveal notice fixture')
      expect(secret).to have_received(:verification?)
      expect(Onetime::Secret.load(secret.identifier)).to be_nil
      expect(notices).to be_empty
    end
  end

  describe 'expiration timeline' do
    it 'removes the receipt on reveal' do
      receipt, secret = spawn
      expect(on_timeline?(receipt)).to be(true)

      secret.reveal!
      expect(on_timeline?(receipt)).to be(false)
    end

    it 'removes the receipt on burn' do
      receipt, secret = spawn
      expect(on_timeline?(receipt)).to be(true)

      expect(secret.burned!).to be(true)
      expect(on_timeline?(receipt)).to be(false)
    end

    # The receipt CAS loser: a second Receipt#revealed! on another loaded
    # instance returns falsy and leaves a (re-added) entry alone.
    it 'leaves the entry when a second Receipt#revealed! loses the CAS' do
      receipt, _secret = spawn
      first            = Onetime::Receipt.load(receipt.identifier)
      second           = Onetime::Receipt.load(receipt.identifier)
      expect(first.revealed!).to be(true)
      Onetime::Receipt.expiration_timeline.add(receipt.identifier, Familia.now.to_f + 3600)

      expect(second.revealed!).to be_falsy
      expect(on_timeline?(receipt)).to be(true)
    end

    it 'leaves the receipt when the reveal is lost' do
      receipt, secret = spawn
      loser           = Onetime::Secret.load(secret.identifier)
      secret.reveal!
      Onetime::Receipt.expiration_timeline.add(receipt.identifier, Familia.now.to_f + 3600)

      expect(loser.reveal!).to be_nil
      expect(on_timeline?(receipt)).to be(true)
    ensure
      Onetime::Receipt.expiration_timeline.remove_element(receipt.identifier) if receipt
    end

    it 'does not fail the reveal when the removal raises' do
      receipt, secret = spawn
      # The sorted set is frozen; stub the class accessor that hands it out.
      # Only the first removal (the reveal's) fails; later ones, such as the
      # cleanup below and in the after hook, reach the real set.
      real_timeline    = Onetime::Receipt.expiration_timeline
      failing_timeline = double('expiration_timeline')
      removals         = 0
      allow(failing_timeline).to receive(:remove_element) do |id|
        removals += 1
        raise Redis::CannotConnectError, 'down' if removals == 1

        real_timeline.remove_element(id)
      end
      allow(Onetime::Receipt).to receive(:expiration_timeline).and_return(failing_timeline)

      expect(secret.reveal!).to eq('reveal notice fixture')
      expect(failing_timeline).to have_received(:remove_element).with(receipt.identifier)
      expect(real_timeline.score(receipt.identifier)).not_to be_nil
      expect(Onetime::Receipt.load(receipt.identifier).state).to eq('revealed')
      expect(notices.size).to eq(1)
    ensure
      real_timeline&.remove_element(receipt.identifier) if receipt
    end

    it 'keeps a pair created with expiration_notifications: false off the timeline' do
      receipt, _secret = spawn(expiration_notifications: false)
      expect(on_timeline?(receipt)).to be(false)
    end
  end

  describe Onetime::Receipt, '#live?' do
    it 'is true for new, previewed and the legacy viewed' do
      expect(%w[new previewed viewed].map { |state| described_class.new(state: state).live? }).to all(be(true))
    end

    it 'is false for every terminal state' do
      states = Onetime::Receipt::TERMINAL_STATES
      expect(states.map { |state| described_class.new(state: state).live? }).to all(be(false))
    end
  end
end
