# tests/unit/ruby/rspec/apps/api/v2/controllers/guest_routes_helpers_spec.rb

require_relative '../../../../spec_helper'
require 'v2/controllers/helpers'

RSpec.describe V2::ControllerHelpers do
  # Create a test class that includes the helpers module
  let(:test_class) do
    Class.new do
      include V2::ControllerHelpers
    end
  end

  let(:helper) { test_class.new }

  describe '#guest_routes_enabled?' do
    context 'when guest_routes config is not present' do
      before do
        allow(OT).to receive(:conf).and_return({
          site: { interface: { api: {} } }
        })
      end

      it 'returns false' do
        expect(helper.guest_routes_enabled?).to be false
      end
    end

    context 'when guest_routes.enabled is false' do
      before do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              api: {
                guest_routes: { enabled: false, conceal: true, reveal: true }
              }
            }
          }
        })
      end

      it 'returns false regardless of operation' do
        expect(helper.guest_routes_enabled?).to be false
        expect(helper.guest_routes_enabled?(:conceal)).to be false
        expect(helper.guest_routes_enabled?(:reveal)).to be false
      end
    end

    context 'when guest_routes.enabled is true' do
      before do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              api: {
                guest_routes: {
                  enabled: true,
                  conceal: true,
                  generate: true,
                  show: true,
                  reveal: false,
                  receipt: false,
                  burn: true
                }
              }
            }
          }
        })
      end

      it 'returns true with no operation specified' do
        expect(helper.guest_routes_enabled?).to be true
      end

      it 'returns true for enabled operations' do
        expect(helper.guest_routes_enabled?(:conceal)).to be true
        expect(helper.guest_routes_enabled?(:generate)).to be true
        expect(helper.guest_routes_enabled?(:show)).to be true
        expect(helper.guest_routes_enabled?(:burn)).to be true
      end

      it 'returns false for disabled operations' do
        expect(helper.guest_routes_enabled?(:reveal)).to be false
        expect(helper.guest_routes_enabled?(:receipt)).to be false
      end

      it 'returns false for unknown operations (secure by default)' do
        expect(helper.guest_routes_enabled?(:unknown_op)).to be false
      end
    end
  end

  describe '#require_guest_routes!' do
    context 'when guest routes are enabled' do
      before do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              api: {
                guest_routes: { enabled: true, conceal: true }
              }
            }
          }
        })
      end

      it 'does not raise an error' do
        expect { helper.require_guest_routes! }.not_to raise_error
        expect { helper.require_guest_routes!(:conceal) }.not_to raise_error
      end
    end

    context 'when guest routes are disabled' do
      before do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              api: {
                guest_routes: { enabled: false }
              }
            }
          }
        })
      end

      it 'raises OT::FormError' do
        expect { helper.require_guest_routes! }.to raise_error(OT::FormError, "Guest API access is not available")
      end
    end

    context 'when specific operation is disabled' do
      before do
        allow(OT).to receive(:conf).and_return({
          site: {
            interface: {
              api: {
                guest_routes: { enabled: true, conceal: false, reveal: true }
              }
            }
          }
        })
      end

      it 'raises OT::FormError for disabled operation' do
        expect { helper.require_guest_routes!(:conceal) }.to raise_error(OT::FormError)
      end

      it 'does not raise for enabled operation' do
        expect { helper.require_guest_routes!(:reveal) }.not_to raise_error
      end
    end
  end
end
