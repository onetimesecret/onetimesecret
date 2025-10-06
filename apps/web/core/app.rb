#!/usr/bin/env ruby
# frozen_string_literal: true

require 'otto'

require_relative 'controllers'

module Core
  class App
    attr_reader :router

    def initialize
      @router = build_router
    end

    def call(env)
      router.call(env)
    end

    private

    def build_router
      routes_path = File.join(Onetime::HOME, 'apps/web/core/routes')
      router      = Otto.new(routes_path)

      # Enable CSP nonce support for enhanced security
      router.enable_csp_with_nonce!(debug: OT.debug?)

      # Register Web Core authentication strategies
      require_relative 'auth_strategies'
      Core::AuthStrategies.register_all(router)

      # Default error responses
      headers             = { 'content-type' => 'text/html' }
      router.not_found    = [404, headers, ['Not Found']]
      router.server_error = [500, headers, ['Internal Server Error']]

      router
    end
  end
end
