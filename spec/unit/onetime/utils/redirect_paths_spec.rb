# spec/unit/onetime/utils/redirect_paths_spec.rb
#
# frozen_string_literal: true

# Unit tests for the server-side internal-redirect validator (#4305).
#
# This is a SECURITY boundary, not a formatting helper: the values it accepts
# are persisted across the signup -> verification-email -> sign-in journey and
# handed back to the SPA as navigation targets. An accepted absolute or
# protocol-relative reference is an open redirect.
#
# The ruleset is duplicated in src/utils/redirect.ts (isValidInternalPath).
# The two MUST stay in lockstep; the "contract parity" block at the bottom
# pins the exact cases named in issue #4305 so a one-sided relaxation shows up
# here as a red test rather than in production as a phishing vector.
#
# Run with:
#   bundle exec rspec spec/unit/onetime/utils/redirect_paths_spec.rb

require 'spec_helper'
require 'onetime/utils/redirect_paths'

RSpec.describe Onetime::Utils::RedirectPaths do
  # Exercise through a bare extender rather than Onetime::Utils so the module
  # is tested in isolation from whatever else Utils mixes in.
  let(:validator) do
    Module.new { extend Onetime::Utils::RedirectPaths }
  end

  describe '#safe_internal_path?' do
    context 'with well-formed internal paths' do
      %w[
        /
        /account
        /account/settings/security
        /secret/abc123
        /files/a..b
        /a%20b
        /caf%C3%A9
        /signin?redirect=%2Fdashboard
      ].each do |path|
        it "accepts #{path.inspect}" do
          expect(validator.safe_internal_path?(path)).to be true
        end
      end

      # Acceptance criterion from #4305: "/secret/abc?view=raw#content" must
      # survive intact. Query and fragment are simply part of the stored
      # string — there is no parsing/re-serialization step to lose them.
      it 'preserves query string and fragment' do
        path = '/secret/abc?view=raw#content'
        expect(validator.safe_internal_path?(path)).to be true
        expect(validator.internal_path_or_nil(path)).to eq(path)
      end
    end

    context 'with absolute and protocol-relative references' do
      [
        'https://attacker.example',
        'http://attacker.example/path',
        '//evil.example',
        '//evil.example/path',
        'HTTPS://attacker.example',
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
      ].each do |path|
        it "rejects #{path.inspect}" do
          expect(validator.safe_internal_path?(path)).to be false
        end
      end
    end

    context 'with backslash variants' do
      # Browsers normalize `\` to `/` in URLs, so `/\evil.example` is read as
      # the protocol-relative `//evil.example`. Rejected at the second
      # character AND anywhere else in the string.
      [
        '/\\evil.example',
        '/\\\\evil.example',
        '/account\\..\\etc',
        '/a\\b',
      ].each do |path|
        it "rejects #{path.inspect}" do
          expect(validator.safe_internal_path?(path)).to be false
        end
      end
    end

    context 'with percent-encoded escapes' do
      # A single decode layer is applied because the browser will itself
      # decode once; the decoded form is what it will act on.
      it 'rejects lowercase encoded traversal (%2e%2e)' do
        expect(validator.safe_internal_path?('/%2e%2e/admin')).to be false
      end

      it 'rejects uppercase encoded traversal (%2E%2E%2F)' do
        expect(validator.safe_internal_path?('/%2E%2E%2Fadmin')).to be false
      end

      it 'rejects an encoded protocol-relative reference (/%2fevil.example)' do
        expect(validator.safe_internal_path?('/%2fevil.example')).to be false
      end

      it 'rejects malformed escapes (decoding failure)' do
        expect(validator.safe_internal_path?('/x%zz')).to be false
        expect(validator.safe_internal_path?('/x%')).to be false
        expect(validator.safe_internal_path?('/x%2')).to be false
      end

      it 'rejects escapes that decode to invalid UTF-8' do
        expect(validator.safe_internal_path?('/%FF%FE')).to be false
      end

      it 'accepts escapes that decode to valid multi-byte UTF-8' do
        expect(validator.safe_internal_path?('/%E2%9C%93')).to be true
      end
    end

    context 'with traversal segments' do
      it 'rejects a plain .. segment' do
        expect(validator.safe_internal_path?('/a/../b')).to be false
      end

      it 'rejects a trailing .. segment' do
        expect(validator.safe_internal_path?('/a/..')).to be false
      end

      it 'rejects a bare /.. path' do
        expect(validator.safe_internal_path?('/..')).to be false
      end

      it 'accepts .. inside a segment (not a traversal)' do
        expect(validator.safe_internal_path?('/files/report..v2')).to be true
      end
    end

    context 'with control characters' do
      it 'rejects a raw newline' do
        expect(validator.safe_internal_path?("/account\nSet-Cookie: a=b")).to be false
      end

      it 'rejects a raw carriage return' do
        expect(validator.safe_internal_path?("/account\r\n")).to be false
      end

      it 'rejects a raw tab' do
        expect(validator.safe_internal_path?("/acc\tount")).to be false
      end

      it 'rejects a NUL byte' do
        expect(validator.safe_internal_path?("/account\x00")).to be false
      end

      it 'rejects DEL' do
        expect(validator.safe_internal_path?("/account\x7F")).to be false
      end

      it 'rejects encoded CRLF (%0d%0a)' do
        expect(validator.safe_internal_path?('/account%0d%0aSet-Cookie:a=b')).to be false
      end
    end

    context 'with structurally invalid input' do
      it 'rejects nil' do
        expect(validator.safe_internal_path?(nil)).to be false
      end

      it 'rejects non-String values' do
        expect(validator.safe_internal_path?(123)).to be false
        expect(validator.safe_internal_path?(['/account'])).to be false
        expect(validator.safe_internal_path?({ path: '/account' })).to be false
      end

      it 'rejects an empty string' do
        expect(validator.safe_internal_path?('')).to be false
      end

      it 'rejects a relative path' do
        expect(validator.safe_internal_path?('account/settings')).to be false
      end

      it 'rejects a leading-whitespace path' do
        expect(validator.safe_internal_path?(' /account')).to be false
      end

      it 'rejects invalid encoding' do
        expect(validator.safe_internal_path?((+"/acc\xFFount").force_encoding(Encoding::UTF_8))).to be false
      end
    end

    context 'with length limits' do
      it 'accepts a path at the 2048-character cap' do
        path = "/#{'a' * 2047}"
        expect(path.length).to eq(2048)
        expect(validator.safe_internal_path?(path)).to be true
      end

      it 'rejects a path one character over the cap' do
        expect(validator.safe_internal_path?("/#{'a' * 2048}")).to be false
      end
    end
  end

  describe '#internal_path_or_nil' do
    it 'returns the value verbatim when valid' do
      expect(validator.internal_path_or_nil('/secret/abc?view=raw#content'))
        .to eq('/secret/abc?view=raw#content')
    end

    it 'returns nil when invalid' do
      expect(validator.internal_path_or_nil('https://attacker.example')).to be_nil
    end

    it 'returns nil for nil' do
      expect(validator.internal_path_or_nil(nil)).to be_nil
    end
  end

  describe 'exposure through Onetime::Utils' do
    it 'is reachable as OT::Utils.safe_internal_path?' do
      expect(Onetime::Utils.safe_internal_path?('/account')).to be true
      expect(Onetime::Utils.safe_internal_path?('//evil.example')).to be false
    end

    it 'does not leak the decoding helper as a public API' do
      expect(Onetime::Utils).not_to respond_to(:percent_decode_once)
    end
  end

  describe 'contract parity with src/utils/redirect.ts (#4305)' do
    # The exact acceptance-criteria cases from the issue. If one of these
    # flips, the frontend validator has to flip with it — or the two sides
    # disagree about what the stored value means.
    {
      '/account/settings/security' => true,
      '/secret/abc?view=raw#content' => true,
      'https://attacker.example' => false,
      '//evil.example' => false,
      '/\\evil.example' => false,
      '/%2e%2e/admin' => false,
    }.each do |path, expected|
      it "#{expected ? 'accepts' : 'rejects'} #{path.inspect}" do
        expect(validator.safe_internal_path?(path)).to be expected
      end
    end
  end
end
