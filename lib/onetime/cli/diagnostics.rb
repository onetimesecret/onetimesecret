# lib/onetime/cli/diagnostics.rb
#
# frozen_string_literal: true

# Shared module for diagnostics CLI commands.
# Provides DSN parsing and HTTP probe helpers used across subcommands.

require 'net/http'
require 'uri'
require 'json'
require 'socket'

module Onetime
  module CLI
    module Diagnostics
      DSN_PATTERN = %r{\Ahttps?://([^@]+)@([^/]+)/(\d+)\z}

      # Parse a Sentry DSN into its components.
      # Returns nil if the DSN is missing or malformed.
      def self.parse_dsn(dsn)
        return nil if dsn.nil? || dsn.strip.empty?

        m = dsn.strip.match(DSN_PATTERN)
        return nil unless m

        { key: m[1], host: m[2], project_id: m[3] }
      end

      def self.store_url(parsed)
        "https://#{parsed[:host]}/api/#{parsed[:project_id]}/store/"
      end

      # Unauthenticated probe of /api/0/ to confirm the Sentry host is reachable.
      def self.check_api(host)
        uri = URI("https://#{host}/api/0/")
        res = Net::HTTP.get_response(uri)
        { ok: res.is_a?(Net::HTTPSuccess), status: res.code.to_i }
      rescue StandardError => ex
        { ok: false, status: 0, error: ex.message }
      end

      # Authenticated POST to the store endpoint to confirm the DSN key is accepted.
      def self.check_store(parsed)
        uri               = URI(store_url(parsed))
        http              = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = uri.scheme == 'https'
        http.open_timeout = 5
        http.read_timeout = 10

        req                  = Net::HTTP::Post.new(uri.path)
        req['X-Sentry-Auth'] = "Sentry sentry_key=#{parsed[:key]}, sentry_version=7"
        req['Content-Type']  = 'application/json'
        req.body             = JSON.generate(message: '[OTS CLI] connectivity probe', level: 'debug')

        res = http.request(req)
        { ok: res.is_a?(Net::HTTPSuccess), status: res.code.to_i }
      rescue StandardError => ex
        { ok: false, status: 0, error: ex.message }
      end

      # Resolve the effective backend DSN respecting the same precedence as the app:
      # SENTRY_DSN_BACKEND → SENTRY_DSN
      def self.backend_dsn
        ENV['SENTRY_DSN_BACKEND'].then { |v| v unless v.to_s.strip.empty? } ||
          ENV['SENTRY_DSN'].then       { |v| v unless v.to_s.strip.empty? }
      end

      # Resolve the effective frontend DSN:
      # SENTRY_DSN_FRONTEND → SENTRY_DSN
      def self.frontend_dsn
        ENV['SENTRY_DSN_FRONTEND'].then { |v| v unless v.to_s.strip.empty? } ||
          ENV['SENTRY_DSN'].then        { |v| v unless v.to_s.strip.empty? }
      end
    end
  end
end
