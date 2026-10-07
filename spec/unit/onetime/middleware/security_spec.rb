# spec/unit/onetime/middleware/security_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Middleware::Security do
  describe 'disabled protection warnings' do
    let(:inner_app) { ->(_env) { [200, {}, ['ok']] } }

    let(:middleware_settings) do
      {
        'utf8_sanitizer' => true,
        'authenticity_token' => true,
        'http_origin' => true,
        'xss_header' => false,
        'frame_options' => false,
        'path_traversal' => true,
        'ip_spoofing' => true,
        'strict_transport' => true,
      }
    end

    before do
      allow(OT).to receive(:conf).and_return('site' => { 'middleware' => middleware_settings })
      allow(OT).to receive(:lw)
      Onetime::Application::MiddlewareStack.reset_warn_once!
    end

    after { Onetime::Application::MiddlewareStack.reset_warn_once! }

    it 'warns at warn level once per process for each disabled component, however many applications build it' do
      3.times { described_class.new(inner_app) }

      aggregate_failures do
        expect(OT).to have_received(:lw)
          .with('[Security] XSSHeader protection DISABLED (site.middleware.xss_header=false)')
          .once
        expect(OT).to have_received(:lw)
          .with('[Security] FrameOptions protection DISABLED (site.middleware.frame_options=false)')
          .once
      end
    end

    it 'does not warn about enabled components' do
      described_class.new(inner_app)

      expect(OT).not_to have_received(:lw).with(/UTF8Sanitizer|AuthenticityToken|PathTraversal/)
    end
  end
end
