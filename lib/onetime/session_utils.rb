# lib/onetime/session_utils.rb
#
# frozen_string_literal: true

require 'base64'

module Onetime
  # SessionUtils — shared helpers for Redis session invalidation.
  #
  # These methods are called from both the Rack logic layer
  # (AccountAPI::Logic::Account::ConfirmEmailChange) and the CLI
  # (Onetime::CLI::ChangeEmailCommand) which has no request context.
  #
  # Session storage format (see lib/onetime/session.rb):
  #   Redis key:   session:<hex_id>
  #   Redis value: base64(json)--hmac
  #   JSON field:  external_id — identifies the owning customer
  #
  module SessionUtils
    LOG_PREFIX = '[session-utils]'

    # Scan Redis for all session keys belonging to +customer+ and delete them.
    # Uses SCAN to avoid blocking on large keyspaces.
    #
    # @param customer [Onetime::Customer] the customer whose sessions to purge
    # @param log_prefix [String] caller-supplied prefix for log lines
    def self.delete_redis_sessions(customer, log_prefix: LOG_PREFIX)
      extid = customer.extid
      return if extid.nil? || extid.to_s.strip.empty?

      dbclient = Familia.dbclient
      deleted  = 0

      dbclient.scan_each(match: 'session:*') do |key|
        session_extid = extract_session_extid(dbclient, key)
        next unless session_extid == extid

        dbclient.del(key)
        deleted += 1
      end

      OT.info "#{log_prefix} Deleted #{deleted} Redis session(s) for cid/#{customer.objid}"
    rescue StandardError => ex
      OT.le "#{log_prefix} Redis session cleanup error: #{ex.message}"
    end

    # Extract the +external_id+ from a stored session value without verifying
    # the HMAC (we are deleting, not trusting the data).
    # Returns nil if the value cannot be decoded.
    #
    # @param dbclient [Redis] Redis connection
    # @param key [String] Redis key to inspect
    # @return [String, nil] the external_id or nil
    def self.extract_session_extid(dbclient, key)
      raw = dbclient.get(key)
      return nil unless raw

      data, _hmac = raw.split('--', 2)
      return nil unless data

      decoded = Base64.decode64(data)
      parsed  = Familia::JsonSerializer.parse(decoded)
      parsed['external_id']
    rescue StandardError
      nil
    end
  end
end
