#!/usr/bin/env ruby
# frozen_string_literal: true

require 'otto'

require_relative 'logic'

module V2
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
      routes_path = File.join(ENV.fetch('ONETIME_HOME'), 'apps/api/v2/routes')
      router      = Otto.new(routes_path)

      # Register authentication strategies
      require 'onetime/auth_strategies'
      Onetime::AuthStrategies.register_all(router)

      # Default error responses
      headers             = { 'content-type' => 'application/json' }
      router.not_found    = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end
  end
end
