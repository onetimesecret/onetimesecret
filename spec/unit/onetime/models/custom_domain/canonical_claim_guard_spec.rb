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

    it 'leaves the claim create! took in place' do
      rec = create

      expect(index.get(ascii_name)).to eq(rec.identifier)
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
          legacy = store_identity_as_plain_strings(create(name_for.call(suffix)), identity_fields)
          before = identity_fields.map { |name| legacy.public_send(name) }
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
        rec = without_canonical_entry(create)
        Familia.dbclient.hdel(rec.dbkey, 'org_id')
        rec.v1_custid = "owner-#{suffix}@example.com"
        rec.save_fields(:v1_custid)
        legacy = reload(rec)

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
