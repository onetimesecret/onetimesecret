# apps/web/auth/spec/config/base_normalize_login_spec.rb
#
# frozen_string_literal: true

# Tests for Rodauth normalize_login configuration in auth/config/base.rb
#
# Issue #2843: Login normalization ensures case-insensitive email matching.
# PostgreSQL uses citext (case-insensitive) but Redis requires exact match.
# The normalize_login block strips whitespace and downcases the login input
# before Rodauth processes it.

require 'spec_helper'
require 'rack/test'

RSpec.describe 'Auth::Config::Base normalize_login', :full_auth_mode, type: :integration do
  include Rack::Test::Methods
  include_context 'auth_rack_test'

  # Test the normalize_login behavior via Rodauth instance
  describe 'login normalization' do
    let(:test_email) { "normalize-test-#{SecureRandom.hex(6)}@example.com" }
    let(:test_password) { 'SecurePassword123!' }

    before do
      # Create account with lowercase email
      create_verified_account(db: test_db, email: test_email, password: test_password)
    end

    after do
      # Clean up test account
      test_db[:account_password_hashes].where(id: test_db[:accounts].where(email: test_email).select(:id)).delete rescue nil
      test_db[:accounts].where(email: test_email).delete rescue nil
    end

    context 'with uppercase email input' do
      it 'authenticates user when login is UPPERCASE' do
        post_json '/auth/login', { login: test_email.upcase, password: test_password }
        expect(last_response.status).to eq(200)
        expect(json_response).to have_key('success')
      end
    end

    context 'with mixed case email input' do
      it 'authenticates user when login is MixedCase' do
        mixed_case_email = test_email.split('@').map.with_index { |p, i|
          i == 0 ? p.chars.map.with_index { |c, j| j.even? ? c.upcase : c.downcase }.join : p.upcase
        }.join('@')

        post_json '/auth/login', { login: mixed_case_email, password: test_password }
        expect(last_response.status).to eq(200)
        expect(json_response).to have_key('success')
      end
    end

    context 'with leading whitespace in email input' do
      it 'authenticates user when login has leading spaces' do
        post_json '/auth/login', { login: "  #{test_email}", password: test_password }
        expect(last_response.status).to eq(200)
        expect(json_response).to have_key('success')
      end
    end

    context 'with trailing whitespace in email input' do
      it 'authenticates user when login has trailing spaces' do
        post_json '/auth/login', { login: "#{test_email}  ", password: test_password }
        expect(last_response.status).to eq(200)
        expect(json_response).to have_key('success')
      end
    end

    context 'with combined uppercase and whitespace' do
      it 'authenticates user when login has both issues' do
        post_json '/auth/login', { login: "  #{test_email.upcase}  ", password: test_password }
        expect(last_response.status).to eq(200)
        expect(json_response).to have_key('success')
      end
    end

    context 'with tabs in whitespace' do
      it 'authenticates user when login has tab characters' do
        post_json '/auth/login', { login: "\t#{test_email.upcase}\t", password: test_password }
        expect(last_response.status).to eq(200)
        expect(json_response).to have_key('success')
      end
    end
  end
end
