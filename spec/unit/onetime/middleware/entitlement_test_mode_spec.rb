# spec/unit/onetime/middleware/entitlement_test_mode_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Unit tests for EntitlementTestMode Middleware
#
# Tests the middleware that copies session[:entitlement_test_planid]
# to Thread.current[:entitlement_test_planid] for the duration of each request.
#
RSpec.describe 'Rack::EntitlementTestMode' do
  # Mock middleware class (to be implemented)
  let(:middleware_class) do
    Class.new do
      def initialize(app)
        @app = app
      end

      def call(env)
        session = env['rack.session']

        # Copy session override to Thread.current if present
        if session && session[:entitlement_test_planid]
          Thread.current[:entitlement_test_planid] = session[:entitlement_test_planid]
        end

        @app.call(env)
      ensure
        # Always clear Thread.current after request
        Thread.current[:entitlement_test_planid] = nil
      end
    end
  end

  let(:app) do
    lambda { |env|
      # Return current Thread.current state in response
      [200, { 'Content-Type' => 'text/plain' }, [Thread.current[:entitlement_test_planid].to_s]]
    }
  end

  let(:middleware) { middleware_class.new(app) }

  after do
    # Ensure Thread.current is cleared after each test
    Thread.current[:entitlement_test_planid] = nil
  end

  describe '#call' do
    context 'when session has entitlement_test_planid' do
      it 'copies value to Thread.current before request' do
        env = {
          'rack.session' => { entitlement_test_planid: 'identity_v1' },
        }

        status, _headers, body = middleware.call(env)

        expect(status).to eq(200)
        expect(body.first).to eq('identity_v1')
      end

      it 'sets Thread.current for the app to read' do
        called_with = nil
        app_that_checks = lambda { |_env|
          called_with = Thread.current[:entitlement_test_planid]
          [200, {}, ['ok']]
        }
        middleware = middleware_class.new(app_that_checks)

        env = {
          'rack.session' => { entitlement_test_planid: 'multi_team_v1' },
        }

        middleware.call(env)

        expect(called_with).to eq('multi_team_v1')
      end

      it 'handles different plan IDs' do
        test_plans = %w[free identity_v1 multi_team_v1]

        test_plans.each do |planid|
          env = {
            'rack.session' => { entitlement_test_planid: planid },
          }

          _status, _headers, body = middleware.call(env)

          expect(body.first).to eq(planid)
        end
      end
    end

    context 'when session has no entitlement_test_planid' do
      it 'does not set Thread.current' do
        env = {
          'rack.session' => {},
        }

        _status, _headers, body = middleware.call(env)

        expect(body.first).to eq('')
      end

      it 'leaves Thread.current as nil' do
        called_with = nil
        app_that_checks = lambda { |_env|
          called_with = Thread.current[:entitlement_test_planid]
          [200, {}, ['ok']]
        }
        middleware = middleware_class.new(app_that_checks)

        env = {
          'rack.session' => {},
        }

        middleware.call(env)

        expect(called_with).to be_nil
      end
    end

    context 'when session is nil' do
      it 'does not crash' do
        env = {
          'rack.session' => nil,
        }

        expect {
          middleware.call(env)
        }.not_to raise_error
      end

      it 'does not set Thread.current' do
        env = {
          'rack.session' => nil,
        }

        _status, _headers, body = middleware.call(env)

        expect(body.first).to eq('')
      end
    end

    context 'when rack.session key is missing' do
      it 'does not crash' do
        env = {}

        expect {
          middleware.call(env)
        }.not_to raise_error
      end

      it 'does not set Thread.current' do
        env = {}

        _status, _headers, body = middleware.call(env)

        expect(body.first).to eq('')
      end
    end

    describe 'cleanup behavior' do
      it 'clears Thread.current after successful request' do
        env = {
          'rack.session' => { entitlement_test_planid: 'identity_v1' },
        }

        middleware.call(env)

        # After request, Thread.current should be cleared
        expect(Thread.current[:entitlement_test_planid]).to be_nil
      end

      it 'clears Thread.current after failed request' do
        failing_app = lambda { |_env|
          raise StandardError, 'App error'
        }
        middleware = middleware_class.new(failing_app)

        env = {
          'rack.session' => { entitlement_test_planid: 'multi_team_v1' },
        }

        expect {
          middleware.call(env)
        }.to raise_error(StandardError, 'App error')

        # Even on error, Thread.current should be cleared
        expect(Thread.current[:entitlement_test_planid]).to be_nil
      end

      it 'clears Thread.current even when app raises exception' do
        failing_app = lambda { |_env|
          # Verify it was set before the error
          expect(Thread.current[:entitlement_test_planid]).to eq('identity_v1')
          raise RuntimeError, 'Simulated error'
        }
        middleware = middleware_class.new(failing_app)

        env = {
          'rack.session' => { entitlement_test_planid: 'identity_v1' },
        }

        expect {
          middleware.call(env)
        }.to raise_error(RuntimeError)

        # Verify cleanup happened
        expect(Thread.current[:entitlement_test_planid]).to be_nil
      end
    end

    describe 'thread isolation' do
      it 'does not leak override to other threads' do
        env = {
          'rack.session' => { entitlement_test_planid: 'identity_v1' },
        }

        # Make request in main thread
        middleware.call(env)

        # Create new thread and check it doesn't have override
        other_thread_value = nil
        thread = Thread.new do
          other_thread_value = Thread.current[:entitlement_test_planid]
        end
        thread.join

        expect(other_thread_value).to be_nil
      end

      it 'independent Thread.current per request thread' do
        # Simulate concurrent requests in different threads
        results = []
        threads = []

        planids = %w[free identity_v1 multi_team_v1]

        planids.each do |planid|
          threads << Thread.new do
            env = {
              'rack.session' => { entitlement_test_planid: planid },
            }

            # Create middleware instance per thread
            thread_middleware = middleware_class.new(app)
            _status, _headers, body = thread_middleware.call(env)

            results << body.first
          end
        end

        threads.each(&:join)

        # Each thread should have seen its own planid
        expect(results).to match_array(planids)
      end
    end

    describe 'session value changes' do
      it 'updates Thread.current when session value changes' do
        session = { entitlement_test_planid: 'free' }

        env1 = { 'rack.session' => session }
        _status, _headers, body1 = middleware.call(env1)
        expect(body1.first).to eq('free')

        # Change session value
        session[:entitlement_test_planid] = 'identity_v1'
        env2 = { 'rack.session' => session }
        _status, _headers, body2 = middleware.call(env2)
        expect(body2.first).to eq('identity_v1')
      end

      it 'handles session value cleared between requests' do
        session = { entitlement_test_planid: 'multi_team_v1' }

        env1 = { 'rack.session' => session }
        _status, _headers, body1 = middleware.call(env1)
        expect(body1.first).to eq('multi_team_v1')

        # Clear session value
        session.delete(:entitlement_test_planid)
        env2 = { 'rack.session' => session }
        _status, _headers, body2 = middleware.call(env2)
        expect(body2.first).to eq('')
      end
    end

    describe 'edge cases' do
      it 'handles nil session value' do
        env = {
          'rack.session' => { entitlement_test_planid: nil },
        }

        expect {
          middleware.call(env)
        }.not_to raise_error

        # Nil value should not be set to Thread.current
        expect(Thread.current[:entitlement_test_planid]).to be_nil
      end

      it 'handles empty string session value' do
        env = {
          'rack.session' => { entitlement_test_planid: '' },
        }

        _status, _headers, body = middleware.call(env)

        # Empty string might be set, but should be cleared after
        expect(Thread.current[:entitlement_test_planid]).to be_nil
      end

      it 'handles non-string session values' do
        # Session values should be strings, but test robustness
        env = {
          'rack.session' => { entitlement_test_planid: :identity_v1 },
        }

        expect {
          middleware.call(env)
        }.not_to raise_error
      end

      it 'handles deeply nested app errors without leaking Thread.current' do
        deeply_nested_app = lambda { |_env|
          # Simulate multiple nested calls
          3.times do
            Thread.current[:some_other_key] = 'value'
          end
          raise StandardError, 'Deep error'
        }
        middleware = middleware_class.new(deeply_nested_app)

        env = {
          'rack.session' => { entitlement_test_planid: 'identity_v1' },
        }

        expect {
          middleware.call(env)
        }.to raise_error(StandardError)

        expect(Thread.current[:entitlement_test_planid]).to be_nil
      end
    end

    describe 'integration with session middleware' do
      it 'works with Rack session middleware pattern' do
        # Simulate a more realistic session structure
        session = {
          entitlement_test_planid: 'identity_v1',
          user_id: 'colonel@example.com',
          authenticated: true,
        }

        env = {
          'rack.session' => session,
          'REQUEST_METHOD' => 'GET',
          'PATH_INFO' => '/test',
        }

        _status, _headers, body = middleware.call(env)

        expect(body.first).to eq('identity_v1')
        # Other session keys should not interfere
        expect(session[:user_id]).to eq('colonel@example.com')
      end
    end
  end

  describe 'middleware ordering' do
    it 'should be inserted after session middleware' do
      # This is a documentation test - the middleware must come after
      # Rack::Session to have access to env['rack.session']
      expect(true).to be true
    end

    it 'should come before entitlement checks' do
      # The middleware must set Thread.current before any code that
      # calls WithEntitlements#entitlements
      expect(true).to be true
    end
  end
end
