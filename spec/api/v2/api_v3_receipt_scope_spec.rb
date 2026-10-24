# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../apps/api/v3/application'

RSpec.describe 'V2/V3 receipt scope regressions', type: :integration do
  before(:all) { Onetime.boot! :test }

  def logic_for(klass, params, owner_id: nil)
    customer = owner_id && double('ReceiptOwner', objid: owner_id, custid: owner_id,
      extid: "ur#{owner_id}", anonymous?: false)
    strategy = double('ReceiptStrategy', user: customer, session: {}, metadata: {},
      auth_method: customer ? 'sessionauth' : 'noauth')
    klass.new(strategy, params)
  end

  [V2, V3].each do |version|
    describe "#{version} scope parsing" do
      [[], ['org'], {}, { 'x' => 'org' }, 123, true].each do |scope|
        it "rejects #{scope.inspect} as a controlled form error" do
          expect do
            logic_for(version::Logic::Secrets::ListReceipts, { 'scope' => scope })
          end.to raise_error(Onetime::FormError, 'Invalid scope')
        end
      end

      [nil, 'org', 'domain', '', 'nonsense', :org].each do |scope|
        it "preserves the existing scalar scope #{scope.inspect}" do
          logic = logic_for(version::Logic::Secrets::ListReceipts, { 'scope' => scope })
          expect(logic.scope).to eq(scope&.to_sym)
        end
      end

      it 'preserves the missing domain filter error' do
        logic = logic_for(version::Logic::Secrets::ListReceipts,
          { 'scope' => 'domain' }, owner_id: 'receipt_owner')
        allow(logic).to receive(:require_entitlement!).and_return(true)
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Domain extid required/)
      end
    end
  end
end
