# spec/apps/api/v1/logic/secrets/show_secret_spec.rb
#
# frozen_string_literal: true

require_relative '../../../../../spec_helper' # correct depth - Mar 22

RSpec.describe V1::Logic::Secrets::ShowSecret do
  let(:session) { double('V1::Session') }
  let(:customer) { double('V1::Customer', anonymous?: false, custid: 'cust123', increment_field: nil ) }
  let(:owner) { double('Owner', custid: 'owner123', verified?: false, anonymous?: false, increment_field: nil ) }

  let(:secret) do
    double('V1::Secret',
      verification: 'false',
      key: 'secret123',
      state?: true,
      owner?: false)
  end

  let(:base_params) do
    {
      key: 'secret123',
      passphrase: 'pass123',
      continue: 'true'
    }
  end

  subject { described_class.new(session, customer, base_params) }

  before(:all) do
    OT.boot!(:test)
  end

  before do
    allow(V1::Secret).to receive(:load).with('secret123').and_return(secret)
    allow(secret).to receive(:load_customer).and_return(owner)
    allow(V1::Customer).to receive(:global).and_return(double('Global', increment_field: true))
  end

  describe '#process' do
    context 'with valid secret' do
      before do
        allow(secret).to receive(:viewable?).and_return(true)
        allow(secret).to receive(:has_passphrase?).and_return(false)
        allow(secret).to receive(:passphrase?).and_return(true)
        allow(secret).to receive(:can_decrypt?).and_return(true)
        allow(secret).to receive(:decrypted_value).and_return('decoded_secret')
        allow(secret).to receive(:truncated?).and_return(false)
        allow(secret).to receive(:original_size).and_return(100)
        allow(secret).to receive(:viewed!)
        allow(secret).to receive(:received!)
        allow(secret).to receive(:verification).and_return('false')
      end

      it 'processes valid secret viewing' do
        subject.process

        expect(subject.show_secret).to be true
        expect(subject.secret_value).to eq('decoded_secret')
        expect(subject.correct_passphrase).to be true
      end
    end

    context 'with passphrase protected secret' do
      before do
        allow(secret).to receive(:viewable?).and_return(true)
        allow(secret).to receive(:has_passphrase?).and_return(true)
        allow(secret).to receive(:passphrase?).with('pass123').and_return(false)
        allow(secret).to receive(:state?).and_return(true)
        allow(secret).to receive(:truncated?).and_return(false)
        allow(secret).to receive(:can_decrypt?).and_return(false)
        allow(secret).to receive(:viewed!)
      end

      it 'handles incorrect passphrase' do
        allow(secret).to receive(:passphrase?).with('pass123').and_return(false)


        subject.process

        expect(subject.correct_passphrase).to be false
      end
    end
  end

  describe '#success_data' do
    before do
      allow(secret).to receive(:safe_dump).and_return({key: 'secret123'})
      subject.instance_variable_set(:@show_secret, true)
      subject.instance_variable_set(:@is_owner, false)
      subject.instance_variable_set(:@correct_passphrase, true)
      subject.instance_variable_set(:@display_lines, 5)
      subject.instance_variable_set(:@one_liner, true)
      subject.instance_variable_set(:@secret_value, 'secret_content')
    end

    it 'returns formatted success data' do
      result = subject.success_data

      expect(result).to include(:record, :details)
      expect(result[:record]).to include(:secret_value)
      expect(result[:details][:show_secret]).to be true
    end
  end
end
