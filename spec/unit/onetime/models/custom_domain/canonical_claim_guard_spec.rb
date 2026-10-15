# spec/unit/onetime/models/custom_domain/canonical_claim_guard_spec.rb
#
# frozen_string_literal: true

# CustomDomain::IdentityGuard: every write path either keeps the canonical
# display-domain claim in step with the stored record or is refused.
#
# canonical_display_domain_index holds one entry per DNS name (its A-label
# form). create! takes the entry before it saves; the guard covers the other
# writers:
#
# - a record that is not stored yet claims its name on a full write, and is
#   refused when another record holds the name or the name has no A-label
#   form;
# - a stored record cannot change its identity fields (display_domain and
#   the parts derived from it) through any writer;
# - a stored record whose identity is unchanged saves without touching the
#   index, including one registered before the index existed.
#
# Real datastore: the claim is a server-side compare-and-set and the guard
# reads the stored hash, so doubles would prove nothing.

require 'spec_helper'
require 'delegate'
require 'securerandom'
require 'onetime/operations/domains/transfer'
require 'onetime/operations/verify_domain'

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Onetime::CustomDomain, 'canonical claim guard', :datastore do
  let(:suffix) { SecureRandom.hex(4) }
  let(:unicode_name) { "bücher-#{suffix}.com" }
  let(:ascii_name) { described_class.canonical_display_domain(unicode_name) }
  let(:index) { described_class.canonical_display_domain_index }
  let(:records) { [] }
  let(:org) { Onetime::Organization.new(display_name: "Guard #{suffix}").tap(&:save) }

  after do
    records.each do |rec|
      rec.destroy! if rec.exists?
    rescue StandardError => ex
      warn "[canonical_claim_guard_spec cleanup] #{ex.class}: #{ex.message}"
    end
    index.remove_field(ascii_name)
    org.destroy! if org.exists?
  end

  def build(name = unicode_name, org_id: org.objid)
    described_class.new(display_domain: name, org_id: org_id).tap { |rec| records << rec }
  end

  def create(name = unicode_name)
    described_class.create!(name, org.objid).tap { |rec| records << rec }
  end

  def reload(rec)
    described_class.find_by_identifier(rec.identifier)
  end

  # Stand-in for a domain registered before canonical_display_domain_index existed.
  def without_canonical_entry(rec)
    index.remove_field(described_class.canonical_display_domain(rec.display_domain))
    rec
  end

  describe 'a record saved without create!' do
    it 'claims its canonical name on save' do
      rec = build

      expect([rec.save, index.get(ascii_name)]).to eq([true, rec.identifier])
    end

    it 'claims its canonical name on save_if_not_exists!' do
      rec = build

      expect([rec.save_if_not_exists!, index.get(ascii_name)]).to eq([true, rec.identifier])
    end

    it 'claims its canonical name on commit_fields' do
      rec = build
      rec.commit_fields

      expect([rec.exists?, index.get(ascii_name)]).to eq([true, rec.identifier])
    end

    it 'is refused when another record holds the name in its other spelling, and writes nothing' do
      holder = create(unicode_name)
      rec    = build(ascii_name)

      expect { rec.save }.to raise_error(Onetime::Problem, 'Domain already registered')
      expect([rec.exists?, index.get(ascii_name), described_class.display_domain_index.get(ascii_name)])
        .to eq([false, holder.identifier, nil])
    end

    it 'is refused when the name has no A-label form, and writes nothing' do
      rec = build("#{'ü' * 70}.com")

      expect { rec.save }.to raise_error(Onetime::Problem, /DNS name limits/)
      expect(rec.exists?).to be(false)
    end

    it 'releases the claim it took when the save does not land' do
      released = []
      real     = index
      recorder = Class.new(SimpleDelegator) do
        define_method(:release_field) do |field, val|
          released << [field, val]
          super(field, val)
        end
      end
      allow(described_class).to receive(:canonical_display_domain_index).and_return(recorder.new(real))
      rec = build(org_id: nil)

      expect { rec.save }.to raise_error(Onetime::Problem, 'Organization ID required')
      expect([rec.exists?, real.get(ascii_name), released]).to eq([false, nil, [[ascii_name, rec.identifier]]])
    end

    it 'keeps the claim when the record was stored but a later step of the save raised' do
      failing = Class.new(SimpleDelegator) do
        define_method(:[]=) { |*| raise Redis::CannotConnectError, 'lookup write failed' }
      end
      allow(described_class).to receive(:objid_lookup).and_return(failing.new(described_class.objid_lookup))
      rec     = build

      expect { rec.save }.to raise_error(Redis::CannotConnectError)
      expect([rec.exists?, index.get(ascii_name)]).to eq([true, rec.identifier])
    end

    it 'leaves the claim create! took in place' do
      rec = create

      expect(index.get(ascii_name)).to eq(rec.identifier)
    end

    # The same canonical-host check create! applies: no record may be
    # registered under a host the deployment serves, or a subdomain of its
    # anchor host's base domain. The canonical host set is stubbed at its
    # single derivation point, so the example does not depend on the lane's
    # site.host.
    context 'when the name overlaps the canonical site host' do
      let(:site_host) { "app.guard-#{suffix}.net" }
      let(:overlap_message) { 'This domain overlaps with the default site domain' }

      before do
        allow(Onetime::Utils::CanonicalHosts).to receive_messages(
          normalized_hosts: [site_host], normalized_anchor_hosts: [site_host],
        )
      end

      after { [site_host, "secrets.guard-#{suffix}.net"].each { |name| index.remove_field(name) } }

      {
        'save' => ->(rec) { rec.save },
        'commit_fields' => ->(rec) { rec.commit_fields },
        'save_if_not_exists!' => ->(rec) { rec.save_if_not_exists! },
      }.each do |writer, write|
        {
          'the site host itself' => ->(suffix) { "app.guard-#{suffix}.net" },
          'a subdomain under the site host\'s base domain' => ->(suffix) { "secrets.guard-#{suffix}.net" },
        }.each do |label, name_for|
          it "refuses #{label} on #{writer}, and writes and claims nothing" do
            name = name_for.call(suffix)
            rec  = build(name)

            expect { write.call(rec) }.to raise_error(Onetime::Problem, overlap_message)
            expect([rec.exists?, index.get(name), described_class.display_domain_index.get(name)])
              .to eq([false, nil, nil])
          end
        end
      end
    end

    it 'does not apply the canonical-host check to a record that is already stored' do
      rec        = create
      allow(Onetime::Utils::CanonicalHosts).to receive_messages(
        normalized_hosts: [unicode_name], normalized_anchor_hosts: [unicode_name],
      )
      rec.status = 'reviewed'

      expect([rec.save, reload(rec).status]).to eq([true, 'reviewed'])
    end
  end

  describe 'a stored record' do
    it 'saves a change to other fields' do
      rec        = create
      rec.status = 'reviewed'

      expect([rec.save, reload(rec).status]).to eq([true, 'reviewed'])
    end

    it 'refuses a changed display_domain on save and leaves the stored record as it was' do
      rec                = create
      rec.display_domain = "other-#{suffix}.com"

      expect { rec.save }.to raise_error(Onetime::Problem, 'The domain name of a custom domain cannot be changed')
      expect(reload(rec).display_domain).to eq(unicode_name)
    end

    it 'refuses a change to a derived field alone' do
      rec     = create
      rec.trd = 'www'

      expect { rec.save }.to raise_error(Onetime::Problem, 'The domain name of a custom domain cannot be changed')
      expect(reload(rec).trd).to eq('')
    end

    it 'refuses a changed identity field on commit_fields' do
      rec             = create
      rec.base_domain = "other-#{suffix}.com"

      expect { rec.commit_fields }.to raise_error(Onetime::Problem, 'The domain name of a custom domain cannot be changed')
      expect(reload(rec).base_domain).to eq(unicode_name)
    end

    it 'refuses to blank the name of a stored record' do
      rec = create
      described_class.new(objid: rec.identifier, org_id: org.objid).tap do |blank|
        expect { blank.commit_fields }.to raise_error(Onetime::Problem, 'The domain name of a custom domain cannot be changed')
      end
      expect(reload(rec).display_domain).to eq(unicode_name)
    end

    # Records written before field values were JSON-encoded hold plain
    # strings. A plain string that reads as a JSON number loads as a number
    # ("1e100" as 1.0e+100, "1.50" as 1.5), and the record must still save.
    # The guard pins its WATCH, the read and the write to one pool
    # connection. The unit lane boots without the pool, and Familia's
    # fallback opens a connection per call, so the WATCH would never hold.
    # These examples install a pool and the provider SetupConnectionPool
    # installs; the concurrent writer uses a connection of its own.
    context 'with a connection pool, as after a full boot' do
      include OnetimeStateHelpers

      let(:other) { described_class.dbclient.dup }

      around do |example|
        snapshot = snapshot_familia_pool_config
        pool     = ConnectionPool.new(size: 2, timeout: 5) { Familia.create_dbclient }
        Onetime::Runtime.update_infrastructure(database_pool: pool)
        Familia.connection_provider = lambda do |_uri|
          stack = Fiber[:ots_pinned_dbclient_stack]
          stack && !stack.empty? ? stack.last : pool.with { |conn| conn }
        end
        example.run
      ensure
        restore_familia_pool_config(snapshot)
        pool&.shutdown(&:close)
      end

      after { other.close }

      # Runs +between+ on the other connection after the guard's first read.
      def between_read_and_write(rec, &between)
        reads = 0
        allow(rec).to receive(:stored_identity).and_wrap_original do |read|
          stored = read.call
          between.call if (reads += 1) == 1
          stored
        end
        -> { reads }
      end

      it 'refuses the save when the record is destroyed in between, and does not store it again' do
        rec   = create
        reads = between_read_and_write(rec) { other.del(rec.dbkey) }

        expect { rec.save }.to raise_error(Onetime::Problem, 'The custom domain no longer exists')
        expect([rec.exists?, reads.call]).to eq([false, 2])
      ensure
        # The raw DEL left the organization's listing behind; destroy! would
        # have removed it.
        rec&.remove_from_organization_domains(org)
      end

      it 'claims a new record on save_if_not_exists! with the pool installed', :aggregate_failures do
        rec = build

        expect(rec.save_if_not_exists!).to be(true)
        expect([reload(rec).display_domain, index.get(ascii_name)]).to eq([unicode_name, rec.identifier])
      end

      it 'refuses save_if_not_exists! on a stored record without changing it', :aggregate_failures do
        rec        = create
        before     = other.hgetall(rec.dbkey)
        rec.status = 'not saved'

        expect { rec.save_if_not_exists! }.to raise_error(Familia::RecordExistsError)
        expect(other.hgetall(rec.dbkey)).to eq(before)
        expect(index.get(ascii_name)).to eq(rec.identifier)
      end

      # rubocop:disable-next RSpec/ExampleLength -- Keep the deletion window and all post-destroy invariants together.
      it 'refuses save_if_not_exists! if destroy! lands after the guard read, without recreating the hash', :aggregate_failures do
        rec   = create
        expect(org.domains.members).to include(rec.identifier)
        expect(described_class::HomepageConfig.exists?(rec.identifier)).to be(true)
        reads = between_read_and_write(rec) do
          # Complete destroy! on a second pooled connection while the first
          # still holds its WATCH. No sleeps or scheduler-dependent race.
          # rubocop:disable-next ThreadSafety/NewThread -- Independent pooled writer, joined before continuing.
          Thread.new { Onetime.with_pinned_dbclient { reload(rec).destroy! } }.value
        end
        allow(rec).to receive(:persist_to_storage).and_call_original

        aggregate_failures do
          expect { rec.save_if_not_exists! }.to raise_error(Familia::RecordExistsError)
          expect([rec.exists?, reads.call, index.get(ascii_name)]).to eq([false, 1, nil])
          expect(org.domains.members).not_to include(rec.identifier)
          expect(described_class::HomepageConfig.exists?(rec.identifier)).to be(false)
          expect(rec).not_to have_received(:persist_to_storage)
        end
      end

      def conflict_after_every_read(rec)
        reads = 0

        allow(rec).to receive(:stored_identity).and_wrap_original do |read|
          stored = read.call
          reads += 1
          other.hset(rec.dbkey, 'updated', reads.to_s)
          stored
        end
        -> { reads }
      end

      [:save, :commit_fields].each do |writer|
        # rubocop:disable-next RSpec/ExampleLength -- Check the failed write and WATCH cleanup on the same pinned connection.
        it "raises after three WATCH conflicts on #{writer}, writes nothing, and clears the WATCH" do
          rec        = create
          rec.status = 'not saved'
          reads      = conflict_after_every_read(rec)

          Onetime.with_pinned_dbclient do |conn|
            aggregate_failures do
              expect { rec.public_send(writer) }
                .to raise_error(Familia::OptimisticLockError, /3 attempts/)
              expect([reads.call, reload(rec).status, index.get(ascii_name)])
                .to eq([3, nil, rec.identifier])
              other.hset(rec.dbkey, 'updated', 'after failure')
              expect(conn.multi { |multi| multi.ping }).to eq(['PONG'])
            end
          end
        end
      end

      # rubocop:disable-next RSpec/ExampleLength -- Keep caller execution, ownership and audit assertions, and cleanup together.
      it 'stops a transfer before reporting success when the owner save exhausts its WATCH retries' do
        rec         = create
        destination = Onetime::Organization.new(display_name: "Destination #{suffix}").tap(&:save)
        reads       = conflict_after_every_read(rec)
        allow(Onetime::ColonelAuditEvent).to receive(:record)
        operation   = Onetime::Operations::Domains::Transfer.new(
          domain: rec, to_org: destination, actor: 'guard-spec', dry_run: false,
        )

        aggregate_failures do
          expect { operation.call }.to raise_error(Familia::OptimisticLockError)
          expect([reads.call, reload(rec).org_id, described_class.owners.get(rec.identifier)])
            .to eq([3, org.objid, org.objid])
          expect(destination.domains.members).not_to include(rec.identifier)
          expect(Onetime::ColonelAuditEvent).to have_received(:record).with(hash_including(result: :failure))
          expect(Onetime::ColonelAuditEvent).not_to have_received(:record).with(hash_including(result: :success))
        end
      ensure
        rec&.remove_from_organization_domains(destination) if destination
        reload(rec)&.destroy! if rec
        destination&.destroy!
      end

      # rubocop:disable-next RSpec/ExampleLength -- Exercise the real caller and compare its persistence result with stored fields.
      it 'reports verification as not persisted when its save exhausts its WATCH retries' do
        rec                = create
        reads              = conflict_after_every_read(rec)
        previous_resolving = rec.resolving
        strategy           = instance_double(
          Onetime::DomainValidation::BaseStrategy,
          validate_ownership: { validated: true, data: { 'txt' => 'match' } },
          check_status: { ready: true, has_ssl: true, is_resolving: true, data: { 'status' => 'ACTIVE_SSL' } },
          proves_ownership?: true,
        )
        operation          = Onetime::Operations::VerifyDomain.new(domain: rec, strategy: strategy)
        allow(operation).to receive(:enqueue_favicon_fetch)

        result = operation.call

        aggregate_failures do
          expect(result.persisted).to be(false)
          expect([reads.call, reload(rec).resolving, reload(rec).verified_confirmed_at])
            .to eq([3, previous_resolving, nil])
        end
      end

      it 'writes again when another writer changed the record in between' do
        rec   = create
        reads = between_read_and_write(rec) { other.hset(rec.dbkey, 'updated', '1') }

        expect([rec.save, reads.call, reload(rec).display_domain]).to eq([true, 2, unicode_name])
      end
    end

    context 'with identity fields stored as plain strings' do
      identity_fields = Onetime::CustomDomain::IdentityGuard::IDENTITY_FIELDS

      def store_identity_as_plain_strings(rec, fields)
        Familia.dbclient.hset(rec.dbkey, fields.to_h { |name| [name.to_s, rec.public_send(name).to_s] })
        reload(rec)
      end

      {
        'an ordinary name' => ->(suffix) { "plain-#{suffix}.example.com" },
        'a second-level label that reads as a number' => ->(suffix) { "x#{suffix}.1e100.net" },
        'a subdomain that reads as a number' => ->(suffix) { "1.50.n#{suffix}.com" },
      }.each do |label, name_for|
        it "saves #{label} and leaves the identity values as they were" do
          legacy        = store_identity_as_plain_strings(create(name_for.call(suffix)), identity_fields)
          before        = identity_fields.map { |name| legacy.public_send(name) }
          legacy.status = 'reviewed'

          expect(legacy.save).to be(true)
          stored = reload(legacy)
          expect([identity_fields.map { |name| stored.public_send(name) }, stored.status]).to eq([before, 'reviewed'])
        end
      end

      it 'passes atomic_write on a name with a label that reads as a number' do
        legacy = store_identity_as_plain_strings(create("x#{suffix}.1e100.net"), identity_fields)

        expect(legacy.atomic_write { legacy.status = 'atomic' }).to be(true)
        expect(reload(legacy).status).to eq('atomic')
      end
    end

    context 'with no canonical entry (registered before the index existed)' do
      it 'saves a change to other fields and adds no entry' do
        rec        = without_canonical_entry(create)
        rec.status = 'reviewed'

        expect([rec.save, reload(rec).status, index.get(ascii_name)]).to eq([true, 'reviewed', nil])
      end

      it 'migrates a v1 owner to an organization and adds no entry' do
        rec           = without_canonical_entry(create)
        Familia.dbclient.hdel(rec.dbkey, 'org_id')
        rec.v1_custid = "owner-#{suffix}@example.com"
        rec.save_fields(:v1_custid)
        legacy        = reload(rec)

        expect(legacy.migrate_to_org!({ "owner-#{suffix}@example.com" => org.objid })).to be(true)
        expect([reload(rec).org_id, index.get(ascii_name)]).to eq([org.objid, nil])
      end
    end
  end

  describe 'partial writes' do
    let(:message) { /can only be written by create! or a full save/ }

    it 'refuses save_fields that names an identity field' do
      rec                = create
      rec.display_domain = "other-#{suffix}.com"

      expect { rec.save_fields(:display_domain) }.to raise_error(Onetime::Problem, message)
      expect(reload(rec).display_domain).to eq(unicode_name)
    end

    it 'refuses multi_field_update that names an identity field' do
      rec = create

      expect { rec.multi_field_update(trd: 'www') }.to raise_error(Onetime::Problem, message)
      expect(reload(rec).trd).to eq('')
    end

    it 'refuses multi_field_fast_write that names an identity field' do
      rec = create

      expect { rec.multi_field_fast_write(sld: 'other') }.to raise_error(Onetime::Problem, message)
      expect(reload(rec).sld).to eq(rec.sld)
    end

    %i[display_domain base_domain subdomain trd tld sld].each do |name|
      it "refuses the #{name}! fast writer given a value" do
        rec = create

        expect { rec.public_send(:"#{name}!", 'other') }.to raise_error(Onetime::Problem, message)
        expect(reload(rec).public_send(name)).to eq(rec.public_send(name))
      end
    end

    it 'still reads through a fast writer given no value' do
      rec = create

      expect(rec.display_domain!).to eq(rec.serialize_value(unicode_name))
    end

    it 'passes partial writes of other fields' do
      rec        = create
      rec.status = 'one'
      rec.save_fields(:status)
      rec.multi_field_update(vhost: '{}')
      rec.multi_field_fast_write(favicon_fetch_status: 'PENDING')
      rec.status!('two')

      expect(reload(rec).then { |r| [r.status, r.vhost, r.favicon_fetch_status] }).to eq(['two', '{}', 'PENDING'])
    end
  end

  describe 'atomic_write' do
    it 'passes a change to other fields' do
      rec = create

      expect(rec.atomic_write { rec.status = 'atomic' }).to be(true)
      expect(reload(rec).status).to eq('atomic')
    end

    it 'refuses an identity change made in its block, and writes nothing from the block' do
      rec = create

      expect do
        rec.atomic_write do
          rec.status = 'atomic'
          rec.trd    = 'www'
        end
      end.to raise_error(Onetime::Problem, 'The domain name of a custom domain cannot be changed')
      expect(reload(rec).then { |r| [r.status, r.trd] }).to eq([nil, ''])
    end

    it 'refuses a record that is not stored yet' do
      rec = build

      expect { rec.atomic_write { rec.status = 'atomic' } }.to raise_error(Onetime::Problem, /not atomic_write/)
      expect([rec.exists?, index.get(ascii_name)]).to eq([false, nil])
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
