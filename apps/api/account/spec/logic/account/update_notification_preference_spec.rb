# apps/api/account/spec/logic/account/update_notification_preference_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'

RSpec.describe AccountAPI::Logic::Account::UpdateNotificationPreference do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'test-cust-123',
      anonymous?: false,
      notify_on_reveal: false,
      'notify_on_reveal=': nil,
      save: true
    )
  end

  let(:session) { { 'csrf' => 'test-csrf-token' } }

  # Mock Otto StrategyResult - the new constructor signature requires this
  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {}
    )
  end

  let(:params) { { 'field' => 'notify_on_reveal', 'value' => 'true' } }

  subject(:logic) do
    described_class.new(strategy_result, params)
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
  end

  describe 'VALID_FIELDS' do
    it 'includes notify_on_reveal' do
      expect(described_class::VALID_FIELDS).to include('notify_on_reveal')
    end

    it 'is frozen' do
      expect(described_class::VALID_FIELDS).to be_frozen
    end
  end

  describe '#preference_field' do
    it 'extracts field name from params' do
      expect(logic.preference_field).to eq('notify_on_reveal')
    end
  end

  describe '#preference_value' do
    it 'converts value string "true" to boolean true' do
      expect(logic.preference_value).to be true
    end

    context 'when value is "false"' do
      let(:params) { { 'field' => 'notify_on_reveal', 'value' => 'false' } }

      it 'converts value string "false" to boolean false' do
        expect(logic.preference_value).to be false
      end
    end
  end

  describe '#old_value' do
    it 'stores old value from customer' do
      allow(customer).to receive(:notify_on_reveal).and_return(true)
      # Need to reinitialize to capture old value
      new_logic = described_class.new(strategy_result, params)
      expect(new_logic.old_value).to be true
    end
  end

  describe '#raise_concerns' do
    context 'when customer is anonymous' do
      let(:customer) do
        instance_double(
          Onetime::Customer,
          objid: 'anon-123',
          anonymous?: true,
          notify_on_reveal: false
        )
      end

      it 'raises form error for anonymous user' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Not authenticated/)
      end
    end

    context 'when field is invalid' do
      let(:params) { { 'field' => 'invalid_field', 'value' => 'true' } }

      it 'raises form error for invalid field' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid field/)
      end
    end

    context 'when customer is authenticated and field is valid' do
      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end

  describe '#process' do
    context 'with valid update' do
      it 'updates the customer preference' do
        expect(customer).to receive(:notify_on_reveal=).with('true')
        expect(customer).to receive(:save)
        logic.process
      end

      it 'logs the update' do
        expect(OT).to receive(:info).with(/update-notification-preference.*notify_on_reveal/)
        logic.process
      end

      it 'returns success data with new value' do
        result = logic.process
        expect(result[:record]).to include('notify_on_reveal' => true)
      end

      it 'returns old value in response' do
        allow(customer).to receive(:notify_on_reveal).and_return(false)
        new_logic = described_class.new(strategy_result, params)
        result = new_logic.process
        expect(result[:old_value]).to be false
      end

      it 'marks field as modified' do
        logic.process
        expect(logic.modified?(:notify_on_reveal)).to be true
      end

      it 'sets greenlighted to true' do
        logic.process
        expect(logic.greenlighted).to be true
      end
    end

    context 'with invalid field' do
      let(:params) { { 'field' => 'invalid_field', 'value' => 'true' } }

      it 'returns nil without updating' do
        expect(customer).not_to receive(:save)
        result = logic.process
        expect(result).to be_nil
      end

      it 'does not set greenlighted' do
        logic.process
        expect(logic.greenlighted).to be false
      end
    end
  end

  describe '#success_data' do
    it 'returns record with preference field and value' do
      data = logic.success_data
      expect(data[:record]).to eq({ 'notify_on_reveal' => true })
    end

    it 'includes old value' do
      allow(customer).to receive(:notify_on_reveal).and_return(true)
      new_logic = described_class.new(strategy_result, params)
      data = new_logic.success_data
      expect(data[:old_value]).to be true
    end
  end

  describe 'toggling preference' do
    context 'when enabling notifications' do
      let(:params) { { 'field' => 'notify_on_reveal', 'value' => 'true' } }

      before do
        allow(customer).to receive(:notify_on_reveal).and_return(false)
      end

      it 'updates from false to true' do
        expect(customer).to receive(:notify_on_reveal=).with('true')
        logic.process
      end
    end

    context 'when disabling notifications' do
      let(:params) { { 'field' => 'notify_on_reveal', 'value' => 'false' } }

      before do
        allow(customer).to receive(:notify_on_reveal).and_return(true)
      end

      it 'updates from true to false' do
        expect(customer).to receive(:notify_on_reveal=).with('false')
        logic.process
      end
    end
  end

  describe 'future extensibility' do
    it 'can be extended with additional notification fields' do
      expect(described_class::VALID_FIELDS).to be_an(Array)
      expect(described_class::VALID_FIELDS.length).to be >= 1
    end
  end
end
