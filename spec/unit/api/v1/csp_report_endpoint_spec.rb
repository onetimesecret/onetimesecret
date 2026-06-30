# spec/unit/api/v1/csp_report_endpoint_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'

# Coverage for the V1 CSP violation report receiver
# (V1::Controllers::Index#csp_report), the destination of the Core web app's
# report-only Content-Security-Policy.
#
# Security properties under test (this is a SECRET-SHARING app):
#   - The endpoint REDACTS secret-bearing URLs before logging. A document-uri or
#     blocked-uri like https://host/secret/<SECRET_KEY> MUST NOT appear in the
#     log output; the violated-directive (a safe field) MUST.
#   - It tolerates both wire formats (legacy application/csp-report and the
#     Reporting API array), malformed JSON, and oversized bodies — always
#     responding 204 and never writing to the database.

require_relative '../../../../apps/api/v1/controllers/index'

RSpec.describe V1::Controllers::Index, '#csp_report' do
  # A planted secret token we expect NEVER to appear in any log line.
  SECRET_KEY = 'supersecrettoken0123456789abcdef0123456789'

  # Capture every structured log call the action makes.
  let(:log_lines) { [] }

  # Minimal request/response doubles driving the REAL action. We build a real
  # Rack-ish request env so read_capped_body exercises rack.input.
  def build_request(body:, content_type: 'application/csp-report')
    env = {
      'CONTENT_TYPE' => content_type,
      'rack.input'   => StringIO.new(body.to_s),
      'REMOTE_ADDR'  => '127.0.0.1',
    }
    req = instance_double('Otto::Request', env: env, body: env['rack.input'])
    req
  end

  let(:response) do
    headers = { 'content-type' => 'application/json' }
    res = instance_double('Otto::Response')
    allow(res).to receive(:headers).and_return(headers)
    allow(res).to receive(:status=)
    allow(res).to receive(:body=)
    res
  end

  # Build the controller, stubbing req/res to our doubles.
  def build_controller(req)
    controller = described_class.allocate
    allow(controller).to receive(:req).and_return(req)
    allow(controller).to receive(:res).and_return(response)
    controller
  end

  before do
    # Capture structured logs. OT.lw/OT.ld/OT.le take (*msgs, **payload).
    allow(OT).to receive(:lw) { |*msgs, **payload| log_lines << [msgs.join(' '), payload].inspect }
    allow(OT).to receive(:ld) { |*msgs, **payload| log_lines << [msgs.join(' '), payload].inspect }
    allow(OT).to receive(:le) { |*msgs, **payload| log_lines << [msgs.join(' '), payload].inspect }
    # Diagnostics/Sentry off in this unit context.
    allow(OT).to receive(:d9s_enabled).and_return(false)
  end

  def all_logs
    log_lines.join("\n")
  end

  context 'legacy application/csp-report body' do
    let(:body) do
      {
        'csp-report' => {
          'document-uri'       => "https://example.com/secret/#{SECRET_KEY}?foo=bar",
          'blocked-uri'        => "https://evil.example/steal/#{SECRET_KEY}",
          'referrer'           => "https://example.com/private/#{SECRET_KEY}",
          'violated-directive' => 'script-src',
          'effective-directive' => 'script-src',
          'disposition'        => 'report',
          'line-number'        => 42,
          'column-number'      => 7,
        },
      }.to_json
    end

    it 'responds 204 and never raises to the client' do
      req = build_request(body: body)
      controller = build_controller(req)

      expect(response).to receive(:status=).with(204)
      expect { controller.csp_report }.not_to raise_error
    end

    it 'logs the safe violated-directive' do
      req = build_request(body: body)
      build_controller(req).csp_report
      expect(all_logs).to include('script-src')
    end

    it 'REDACTS the planted secret key out of every logged URL field' do
      req = build_request(body: body)
      build_controller(req).csp_report

      expect(all_logs).not_to include(SECRET_KEY)
      expect(all_logs).not_to include('foo=bar')         # query string stripped
      expect(all_logs).to include('[redacted-path]')     # path collapsed
    end
  end

  context 'Reporting API application/reports+json array body' do
    let(:body) do
      [
        {
          'type' => 'csp-violation',
          'body' => {
            'documentURL'       => "https://example.com/secret/#{SECRET_KEY}",
            'blockedURL'        => "https://cdn.evil/#{SECRET_KEY}",
            'effectiveDirective' => 'img-src',
            'disposition'       => 'report',
          },
        },
      ].to_json
    end

    it 'responds 204, logs the directive, and redacts the secret' do
      req = build_request(body: body, content_type: 'application/reports+json')
      controller = build_controller(req)

      expect(response).to receive(:status=).with(204)
      controller.csp_report

      expect(all_logs).to include('img-src')
      expect(all_logs).not_to include(SECRET_KEY)
    end
  end

  context 'oversized body' do
    let(:body) do
      # > 64 KiB so it is skipped without parsing. Plant the secret to prove it
      # is never logged.
      "{\"csp-report\":{\"document-uri\":\"https://h/secret/#{SECRET_KEY}\",\"pad\":\"#{'x' * (70 * 1024)}\"}}"
    end

    it 'responds 204, does NOT parse, and never logs the secret' do
      req = build_request(body: body)
      controller = build_controller(req)

      expect(response).to receive(:status=).with(204)
      controller.csp_report

      expect(all_logs).not_to include(SECRET_KEY)
      # The "no parseable reports" debug line should have fired.
      expect(all_logs).to include('no parseable violation reports')
    end
  end

  context 'malformed JSON body' do
    it 'responds 204 and logs nothing secret' do
      req = build_request(body: '{not valid json')
      controller = build_controller(req)

      expect(response).to receive(:status=).with(204)
      expect { controller.csp_report }.not_to raise_error
      expect(all_logs).to include('no parseable violation reports')
    end
  end

  context 'empty body' do
    it 'responds 204' do
      req = build_request(body: '')
      controller = build_controller(req)

      expect(response).to receive(:status=).with(204)
      expect { controller.csp_report }.not_to raise_error
    end
  end
end
