# frozen_string_literal: true

require 'rack'
require 'stringio'
require_relative '../security/saml_callback_store'

module Onetime
  module Middleware
    module SamlCallbackTransport
      HANDLE_PARAM   = 'saml_handle'
      PREPARED       = 'onetime.saml_callback_prepared'
      MAX_BODY_BYTES = 500_000
      HEADERS        = {
        'content-type' => 'text/plain',
        'cache-control' => 'no-store',
        'referrer-policy' => 'no-referrer',
      }.freeze

      # Keep credentials out of ordinary Rack query/body capture. The private
      # hand-off is never serialized and is removed before outer logging runs.
      class Payload
        attr_reader :response, :handle

        def initialize(response: nil, handle: nil)
          @response = response
          @handle   = handle
        end

        def inspect
          '[SAML callback transport data]'
        end
        alias to_s inspect
      end

      def self.callback?(env)
        Rack::Request.new(env).path.casecmp?("/auth/sso/#{ENV.fetch('SAML_ROUTE_NAME', 'saml')}/callback")
      end

      def self.callback_post?(env)
        env['REQUEST_METHOD'] == 'POST' && callback?(env)
      end

      def self.clear_request_data(env)
        env['QUERY_STRING']   = ''
        %w[REQUEST_URI ORIGINAL_FULLPATH RAW_URI].each do |key|
          env[key] = env[key].split('?', 2).first if env[key].is_a?(String)
        end
        env.delete('HTTP_REFERER')
        %w[rack.request.query_hash rack.request.form_hash rack.request.form_pairs].each do |key|
          env[key]&.clear
          env.delete(key)
        end
        %w[rack.request.query_string rack.request.form_vars rack.request.form_input].each { |key| env.delete(key) }
        env['rack.input']     = StringIO.new('')
        env['CONTENT_LENGTH'] = '0'
      end

      # Before parsers, Session, RequestLogger and Sentry. Raw callback data
      # must not reach their generic request capture, even with PII/debug on.
      # Ignore cookies on POST even for None: transport cannot mutate the
      # initiating session or run Connect/tenant hooks with a temporary one.
      class Boundary
        def initialize(app)
          @app = app
        end

        def call(env)
          callback = SamlCallbackTransport.callback?(env)
          return @app.call(env) unless callback

          payload, error = prepare(env)
          SamlCallbackTransport.clear_request_data(env)
          return error if error

          post                      = env['REQUEST_METHOD'] == 'POST'
          if post
            env['HTTP_COOKIE'] = ''
            env.delete('rack.request.cookie_hash')
          end
          env[PREPARED]             = payload
          status, headers, response = @app.call(env)
          headers                   = headers.reject { |key, _| post && key.downcase == 'set-cookie' }.merge(
            'cache-control' => 'no-store', 'referrer-policy' => 'no-referrer',
          )
          [status, headers, response]
        ensure
          if callback
            SamlCallbackTransport.clear_request_data(env)
            env.delete(PREPARED)
          end
        end

        private

        def prepare(env)
          request = Rack::Request.new(env)
          unless request.post?
            # No SAMLResponse or unrelated query parameters are forwarded.
            # Bound the GET too, before asking Rack to parse a hostile query.
            return [nil, [414, HEADERS.dup, ['SAML callback URL too large']]] if env['QUERY_STRING'].to_s.bytesize > 4096

            return [Payload.new(handle: request.GET[HANDLE_PARAM]), nil]
          end
          return [nil, [415, HEADERS.dup, ['SAML callback requires a URL-encoded form']]] unless request.media_type == 'application/x-www-form-urlencoded'
          return [nil, [413, HEADERS.dup, ['SAML callback too large']]] if env['CONTENT_LENGTH'].to_i > MAX_BODY_BYTES

          body = env.fetch('rack.input').read(MAX_BODY_BYTES + 1)
          return [nil, [413, HEADERS.dup, ['SAML callback too large']]] if body.bytesize > MAX_BODY_BYTES

          params = Rack::Utils.parse_nested_query(body)
          [Payload.new(response: params['SAMLResponse']), nil]
        rescue StandardError
          [nil, [400, HEADERS.dup, ['Invalid SAML callback']]]
        end
      end

      # Inside the auth security profile, before Rodauth/OmniAuth. Only here
      # may a GET expose the handle to the strategy's request.GET accessor;
      # ensure removes it before outer instrumentation observes the response
      # or captures an exception. The raw POST body is never restored.
      class Stage
        def initialize(app)
          @app = app
        end

        def call(env)
          callback = SamlCallbackTransport.callback?(env)
          return @app.call(env) unless callback
          return stage_post(env) if env['REQUEST_METHOD'] == 'POST'

          payload = env[PREPARED]
          if env['REQUEST_METHOD'] == 'GET' && payload.is_a?(Payload) && payload.handle
            Rack::Request.new(env).GET[HANDLE_PARAM] = payload.handle
          end
          @app.call(env)
        ensure
          SamlCallbackTransport.clear_request_data(env) if callback
        end

        private

        def stage_post(env)
          env['rack.session.options'][:skip] = true if env['rack.session.options']
          payload                            = env[PREPARED]
          return [503, HEADERS.dup, ['SAML callback transport unavailable']] unless payload.is_a?(Payload)

          request  = Rack::Request.new(env)
          response = payload.response
          store    = Onetime::Security::SamlCallbackStore
          return [400, HEADERS.dup, ['Invalid SAML callback']] unless response.is_a?(String) && response.bytesize.between?(1, store::MAX_RESPONSE_BYTES)

          handle = store.stage(
            response: response,
            scope: store.scope(env),
            source: env['otto.client_ip'] || env['REMOTE_ADDR'],
          )
          [303, HEADERS.merge('location' => "#{request.path}?#{HANDLE_PARAM}=#{handle}"), []]
        rescue Onetime::Security::SamlCallbackStore::CapacityExceeded
          [429, HEADERS.merge('retry-after' => Onetime::Security::SamlCallbackStore::TTL.to_s), ['SAML callback capacity exceeded']]
        rescue StandardError
          [503, HEADERS.dup, ['SAML callback transport unavailable']]
        end
      end
    end
  end
end
