# apps/api/v1/spec/controllers/show_receipt_recent_spec.rb
#
# frozen_string_literal: true

# Tests for Bug #2: /private/recent crashes because show_receipt_recent
# passed safe_dump hashes (not Receipt model objects) to receipt_hsh.
#
# receipt_hsh calls md.to_h, md.identifier, md.secret_ttl, and
# md.current_expiration — all of which require Receipt model objects.
# When ShowReceiptList returned hashes from safe_dump, these method calls
# crashed with NoMethodError.
#
# The fix in show_receipt_list.rb line 33 changed from returning
# safe_dump hashes to returning Receipt model objects via
# find_by_identifier.

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')
require 'v1/controllers'

RSpec.describe V1::Controllers::Index, '#show_receipt_recent' do
  include_context "rack_test_context"

  let(:request) { rack_request }
  let(:response) { rack_response }

  let(:app) { described_class.new request, response }

  let(:session) do
    double('Session',
      sessid: 'test_session_123',
      authenticated?: true,
      anonymous?: false,
      ipaddress: '127.0.0.1',
      external_identifier: 'ext123')
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      custid: 'test@example.com',
      anonymous?: false,
      active?: true,
      verified?: true,
      role: 'customer',
      increment_field: nil,
      email: 'test@example.com')
  end

  before do
    allow(app).to receive(:sess).and_return(session)
    allow(app).to receive(:cust).and_return(customer)
    allow(app).to receive(:req).and_return(request)
    allow(app).to receive(:res).and_return(response)
    allow(app).to receive(:locale).and_return('en')
    allow(app).to receive(:authorized).and_yield
  end

  describe '#show_receipt_recent' do
    let(:logic) { instance_double(V1::Logic::Secrets::ShowReceiptList) }

    before do
      allow(V1::Logic::Secrets::ShowReceiptList).to receive(:new)
        .with(session, customer, request.params, 'en')
        .and_return(logic)
      allow(logic).to receive(:raise_concerns)
      allow(logic).to receive(:process)
    end

    context 'when there are no recent receipts' do
      before do
        allow(logic).to receive(:receipts).and_return([])
      end

      it 'returns an empty JSON array' do
        expect(app).to receive(:json).with([])
        app.show_receipt_recent
      end
    end

    context 'when there are recent receipts (model objects)' do
      let(:receipt1) do
        double('Onetime::Receipt',
          to_h: {
            'owner_id' => 'cust_uuid',
            'secret_identifier' => 'secret_1',
            'recipients' => '',
            'updated' => '1700000000',
            'created' => '1699999000',
            'received' => '',
            'revealed' => '',
            'share_domain' => '',
            'state' => 'new',
          },
          identifier: 'receipt_1',
          secret_ttl: 3600,
          current_expiration: 7000)
      end

      let(:receipt2) do
        double('Onetime::Receipt',
          to_h: {
            'owner_id' => 'cust_uuid',
            'secret_identifier' => 'secret_2',
            'recipients' => '',
            'updated' => '1700000100',
            'created' => '1699999100',
            'received' => '',
            'revealed' => '',
            'share_domain' => '',
            'state' => 'previewed',
          },
          identifier: 'receipt_2',
          secret_ttl: 7200,
          current_expiration: 14000)
      end

      before do
        allow(logic).to receive(:receipts).and_return([receipt1, receipt2])
      end

      it 'returns an array of receipt hashes (not error)' do
        captured = nil
        allow(app).to receive(:json) { |arg| captured = arg }

        app.show_receipt_recent

        expect(captured).to be_an(Array)
        expect(captured.length).to eq(2)
      end

      it 'each hash contains V1 field names' do
        captured = nil
        allow(app).to receive(:json) { |arg| captured = arg }

        app.show_receipt_recent

        captured.each do |hash|
          expect(hash).to have_key('metadata_key')
          expect(hash).to have_key('custid')
          expect(hash).to have_key('state')
        end
      end

      it 'removes secret_key from each hash (privacy)' do
        captured = nil
        allow(app).to receive(:json) { |arg| captured = arg }

        app.show_receipt_recent

        captured.each do |hash|
          expect(hash).not_to have_key('secret_key')
        end
      end

      it 'maps state correctly (previewed -> viewed)' do
        captured = nil
        allow(app).to receive(:json) { |arg| captured = arg }

        app.show_receipt_recent

        states = captured.map { |h| h['state'] }
        expect(states).to include('new')
        expect(states).to include('viewed') # previewed -> viewed
      end
    end

    context 'when receipts list contains nil entries' do
      let(:receipt1) do
        double('Onetime::Receipt',
          to_h: {
            'owner_id' => 'cust_uuid',
            'secret_identifier' => 'secret_1',
            'recipients' => '',
            'updated' => '1700000000',
            'created' => '1699999000',
            'received' => '',
            'revealed' => '',
            'share_domain' => '',
            'state' => 'new',
          },
          identifier: 'receipt_1',
          secret_ttl: 3600,
          current_expiration: 7000)
      end

      before do
        allow(logic).to receive(:receipts).and_return([nil, receipt1, nil])
      end

      it 'filters out nil entries and returns only valid hashes' do
        captured = nil
        allow(app).to receive(:json) { |arg| captured = arg }

        app.show_receipt_recent

        expect(captured).to be_an(Array)
        expect(captured.length).to eq(1)
      end
    end
  end
end
