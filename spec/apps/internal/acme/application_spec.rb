# spec/apps/internal/acme/application_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require_relative '../../../../apps/internal/acme/application'

RSpec.describe Internal::ACME::Application, type: :request do
  # These tests now work with Otto's plain-text routes API

  # Uncomment when ready to enable tests
  # before(:all) do
  #   skip 'Requires Otto API compatibility investigation'
  # end

  let(:app) { described_class.new }

  describe 'GET /ask' do
    let(:verified_domain) do
      double('CustomDomain',
             display_domain: 'verified.example.com',
             ready?: true)
    end

    let(:unverified_domain) do
      double('CustomDomain',
             display_domain: 'unverified.example.com',
             ready?: false)
    end

    before do
      # Mock localhost request by default
      allow_any_instance_of(Rack::Request).to receive(:env)
        .and_return({ 'REMOTE_ADDR' => '127.0.0.1' })
    end

    context 'with verified domain' do
      before do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .with('verified.example.com')
          .and_return(verified_domain)
      end

      it 'returns 200 OK' do
        get '/ask', domain: 'verified.example.com'
        expect(last_response.status).to eq(200)
      end

      it 'returns OK text' do
        get '/ask', domain: 'verified.example.com'
        expect(last_response.body).to eq('OK')
      end

      it 'sets content-type to text/plain' do
        get '/ask', domain: 'verified.example.com'
        expect(last_response.headers['content-type']).to eq('text/plain')
      end

      it 'logs the check result' do
        expect(OT).to receive(:info).with(/Domain check: verified\.example\.com -> 200/)
        get '/ask', domain: 'verified.example.com'
      end
    end

    context 'with unverified domain' do
      before do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .with('unverified.example.com')
          .and_return(unverified_domain)
      end

      it 'returns 403 Forbidden' do
        get '/ask', domain: 'unverified.example.com'
        expect(last_response.status).to eq(403)
      end

      it 'returns Forbidden text' do
        get '/ask', domain: 'unverified.example.com'
        expect(last_response.body).to eq('Forbidden')
      end

      it 'logs the check result' do
        expect(OT).to receive(:info).with(/Domain check: unverified\.example\.com -> 403/)
        get '/ask', domain: 'unverified.example.com'
      end
    end

    context 'with non-existent domain' do
      before do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .with('nonexistent.example.com')
          .and_return(nil)
      end

      it 'returns 403 Forbidden' do
        get '/ask', domain: 'nonexistent.example.com'
        expect(last_response.status).to eq(403)
      end

      it 'returns Forbidden text' do
        get '/ask', domain: 'nonexistent.example.com'
        expect(last_response.body).to eq('Forbidden')
      end
    end

    context 'without domain parameter' do
      it 'returns 400 Bad Request' do
        get '/ask'
        expect(last_response.status).to eq(400)
      end

      it 'returns descriptive error message' do
        get '/ask'
        expect(last_response.body).to include('domain parameter required')
      end

      it 'logs missing parameter' do
        expect(OT).to receive(:ld).with(/Missing domain parameter/)
        get '/ask'
      end
    end

    context 'with empty domain parameter' do
      it 'returns 400 Bad Request' do
        get '/ask', domain: ''
        expect(last_response.status).to eq(400)
      end
    end

    context 'when database error occurs' do
      before do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .and_raise(StandardError, 'Database connection failed')
      end

      it 'logs the error' do
        expect(OT).to receive(:le).with(/Error checking domain/)
        get '/ask', domain: 'error.example.com'
      end

      it 'returns 403 Forbidden (fail closed)' do
        allow(OT).to receive(:le)
        get '/ask', domain: 'error.example.com'
        expect(last_response.status).to eq(403)
      end
    end
  end

  describe 'LocalhostOnly middleware' do
    let(:verified_domain) do
      double('CustomDomain', display_domain: 'example.com', ready?: true)
    end

    before do
      allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
        .and_return(verified_domain)
    end

    context 'with IPv4 localhost' do
      it 'allows request from 127.0.0.1' do
        header 'REMOTE_ADDR', '127.0.0.1'
        get '/ask', domain: 'example.com'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with IPv6 localhost' do
      it 'allows request from ::1' do
        header 'REMOTE_ADDR', '::1'
        get '/ask', domain: 'example.com'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with IPv4-mapped IPv6 localhost' do
      it 'allows request from ::ffff:127.0.0.1' do
        header 'REMOTE_ADDR', '::ffff:127.0.0.1'
        get '/ask', domain: 'example.com'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with external IPv4 address' do
      it 'returns 401 Unauthorized from 192.168.1.1' do
        header 'REMOTE_ADDR', '192.168.1.1'
        get '/ask', domain: 'example.com'
        expect(last_response.status).to eq(401)
      end

      it 'returns descriptive error message' do
        header 'REMOTE_ADDR', '192.168.1.1'
        get '/ask', domain: 'example.com'
        expect(last_response.body).to include('localhost only')
      end

      it 'logs unauthorized access attempt' do
        expect(OT).to receive(:le).with(/Unauthorized access attempt from 192\.168\.1\.1/)
        header 'REMOTE_ADDR', '192.168.1.1'
        get '/ask', domain: 'example.com'
      end
    end

    context 'with external IPv6 address' do
      it 'returns 401 Unauthorized' do
        header 'REMOTE_ADDR', '2001:0db8::1'
        get '/ask', domain: 'example.com'
        expect(last_response.status).to eq(401)
      end
    end

    context 'with public IP address' do
      it 'returns 401 Unauthorized from 8.8.8.8' do
        header 'REMOTE_ADDR', '8.8.8.8'
        get '/ask', domain: 'example.com'
        expect(last_response.status).to eq(401)
      end
    end

    context 'with private network address' do
      it 'returns 401 Unauthorized from 10.0.0.1' do
        header 'REMOTE_ADDR', '10.0.0.1'
        get '/ask', domain: 'example.com'
        expect(last_response.status).to eq(401)
      end
    end
  end

  describe '#domain_allowed?' do
    subject(:application) { described_class.new }

    context 'with nil domain' do
      it 'returns false' do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .with('test.com')
          .and_return(nil)

        result = application.send(:domain_allowed?, 'test.com')
        expect(result).to be false
      end
    end

    context 'with domain that is not ready' do
      let(:domain) { double('CustomDomain', ready?: false) }

      it 'returns false' do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .and_return(domain)

        result = application.send(:domain_allowed?, 'test.com')
        expect(result).to be false
      end
    end

    context 'with domain that is ready' do
      let(:domain) { double('CustomDomain', ready?: true) }

      it 'returns true' do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .and_return(domain)

        result = application.send(:domain_allowed?, 'test.com')
        expect(result).to be true
      end
    end

    context 'when exception occurs' do
      it 'logs error and returns false' do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .and_raise(StandardError, 'Test error')

        expect(OT).to receive(:le).with(/Error checking domain/)
        result = application.send(:domain_allowed?, 'test.com')
        expect(result).to be false
      end
    end
  end

  describe 'routing' do
    context 'valid endpoint' do
      before do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .and_return(double(ready?: true))
      end

      it 'routes GET /ask' do
        get '/ask', domain: 'example.com'
        expect(last_response.status).not_to eq(404)
      end
    end

    context 'invalid endpoint' do
      it 'returns 404 for unknown paths' do
        get '/invalid'
        expect(last_response.status).to eq(404)
      end

      it 'returns Not Found message' do
        get '/invalid'
        expect(last_response.body).to eq('Not Found')
      end
    end

    context 'wrong HTTP method' do
      it 'returns 404 for POST to /ask' do
        post '/ask', domain: 'example.com'
        expect(last_response.status).to eq(404)
      end
    end
  end
end
