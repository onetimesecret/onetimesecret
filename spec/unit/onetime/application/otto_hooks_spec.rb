# spec/unit/onetime/application/otto_hooks_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Application::OttoHooks do
  # Minimal host: OttoHooks is a mixin, so include it in a bare class.
  let(:host_class) { Class.new { include Onetime::Application::OttoHooks } }
  let(:host)       { host_class.new }

  # Stand-in for the Otto router. We only assert OUR wiring (the gate + the
  # ranges handed over); Otto's own client_ipaddress / secure? resolution from
  # that trust list is covered by the gem.
  let(:router) { instance_double(Otto) }

  describe '#configure_otto_trusted_proxies' do
    context 'when trusted_proxy is enabled' do
      before do
        allow(Onetime::Application::MiddlewareStack)
          .to receive(:trusted_proxy_enabled?).and_return(true)
      end

      it 'hands the router the shared private-proxy ranges' do
        expect(router).to receive(:add_trusted_proxy)
          .with(Onetime::Application::MiddlewareStack::PRIVATE_PROXY_RANGES)

        host.configure_otto_trusted_proxies(router)
      end
    end

    context 'when trusted_proxy is disabled' do
      before do
        allow(Onetime::Application::MiddlewareStack)
          .to receive(:trusted_proxy_enabled?).and_return(false)
      end

      it 'leaves the router trust list empty (direct-connection mode)' do
        expect(router).not_to receive(:add_trusted_proxy)

        host.configure_otto_trusted_proxies(router)
      end
    end
  end
end
