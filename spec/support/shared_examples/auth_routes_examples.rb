# spec/support/shared_examples/auth_routes_examples.rb
#
# frozen_string_literal: true

# Shared examples for testing auth routes across different modes.
#
# Usage:
#   RSpec.describe 'Auth Routes', :full_auth_mode do
#     include_context 'auth_rack_test'
#     it_behaves_like 'common health routes'
#     it_behaves_like 'full mode login routes'
#   end

# Routes that work regardless of auth mode
RSpec.shared_examples 'common health routes' do
  describe 'GET /api/v2/status' do
    it 'returns 200' do
      get '/api/v2/status'
      expect(last_response.status).to eq(200)
    end
  end

  describe 'GET /' do
    it 'returns 200' do
      get '/'
      expect(last_response.status).to eq(200)
    end
  end
end

# Login routes available in full mode
RSpec.shared_examples 'full mode login routes' do
  describe 'POST /auth/login' do
    context 'with invalid credentials' do
      it 'returns 401' do
        post_json '/auth/login', { login: 'invalid@example.com', password: 'wrong' }
        expect(last_response.status).to eq(401)
      end

      it 'returns JSON error' do
        post_json '/auth/login', { login: 'invalid@example.com', password: 'wrong' }
        expect(json_response).to have_key('error')
      end
    end
  end

  describe 'POST /auth/create-account' do
    context 'with valid data' do
      let(:new_email) { "new-#{SecureRandom.hex(8)}@example.com" }

      it 'returns success status' do
        post_json '/auth/create-account', {
          login: new_email,
          password: 'Test1234!@',
          'password-confirm': 'Test1234!@'
        }
        expect(last_response.status).to be_between(200, 201)
      end
    end

    context 'with mismatched passwords' do
      it 'returns error' do
        post_json '/auth/create-account', {
          login: "mismatch-#{SecureRandom.hex(8)}@example.com",
          password: 'Test1234!@',
          'password-confirm': 'Different!@'
        }
        expect(last_response.status).to eq(422).or eq(400)
      end
    end
  end

  describe 'POST /auth/reset-password' do
    it 'returns success for any email (security: no email enumeration)' do
      post_json '/auth/reset-password', { login: 'nonexistent@example.com' }
      # Should return success even for non-existent emails
      expect(last_response.status).to be_between(200, 202)
    end
  end
end

# Routes that should return 404 in simple mode (Rodauth not loaded)
RSpec.shared_examples 'simple mode returns 404 for auth routes' do
  describe 'POST /auth/login' do
    it 'returns 404' do
      post '/auth/login', { login: 'test@example.com', password: 'password' }
      expect(last_response.status).to eq(404)
    end
  end

  describe 'POST /auth/create-account' do
    it 'returns 404' do
      post '/auth/create-account', { login: 'new@example.com', password: 'password' }
      expect(last_response.status).to eq(404)
    end
  end

  describe 'POST /auth/reset-password' do
    it 'returns 404' do
      post '/auth/reset-password', { login: 'reset@example.com' }
      expect(last_response.status).to eq(404)
    end
  end
end

# Routes that redirect in disabled mode (auth completely off)
RSpec.shared_examples 'disabled mode redirects auth routes' do
  describe 'POST /auth/login' do
    it 'redirects' do
      post '/auth/login', { login: 'test@example.com', password: 'password' }
      expect(last_response.status).to eq(302)
    end
  end

  describe 'POST /auth/create-account' do
    it 'redirects' do
      post '/auth/create-account', { login: 'new@example.com', password: 'password' }
      expect(last_response.status).to eq(302)
    end
  end

  describe 'POST /auth/logout' do
    it 'redirects' do
      post '/auth/logout'
      expect(last_response.status).to eq(302)
    end
  end
end

# Authenticated routes requiring login
RSpec.shared_examples 'authenticated routes require auth' do
  describe 'GET /auth/account' do
    it 'returns 401 without authentication' do
      get_json '/auth/account'
      expect(last_response.status).to eq(401)
    end
  end

  describe 'GET /auth/active-sessions' do
    it 'returns 401 without authentication' do
      get_json '/auth/active-sessions'
      expect(last_response.status).to eq(401)
    end
  end

  describe 'POST /auth/remove-all-active-sessions' do
    it 'returns 401 without authentication' do
      post_json '/auth/remove-all-active-sessions'
      expect(last_response.status).to eq(401)
    end
  end
end
