# lib/onetime/session/recent_reauth.rb
#
# frozen_string_literal: true

require_relative 'namespace'
require_relative 'sidecar'
require_relative 'surface'

module Onetime
  # Single-use proof of a completed local ceremony for sensitive actions such
  # as identity attachment. Record only after the local primary and all
  # required MFA complete. A passkey counts when Rodauth accepts it as meeting
  # the MFA requirement; mailbox, SSO, and existing-session proof never count.
  #
  # The encrypted sidecar binds the proof to the Rack session ID. {satisfied?}
  # atomically consumes it and checks the account, exact resolved surface,
  # allowed local primary, and caller-supplied age limit. Missing, invalid, or
  # unverifiable proof fails closed.
  module Session::RecentReauth
    KEY = 'recent_reauth'

    # A proof is valid only when its first completed method is an explicitly
    # reviewed local primary. Positive matching keeps unknown, mailbox, and
    # federated methods fail-closed.
    LOCAL_PRIMARIES = %w[password webauthn].freeze

    # Maximum age of a proof that may mint a Connect intent (#4411). The
    # sidecar TTL ({Session::Sidecar::FIELDS} 'recent_reauth', 900s) is only a
    # storage backstop; this window is the authoritative policy and is
    # deliberately the same length as the intent's own TTL — a proof is meant
    # to be spent by the very next Connect initiation, not banked.
    CONNECT_MAX_AGE = 300

    class << self
      # Record a proof in the session-bound sidecar. Returns the stored payload, or
      # nil when the request has no authoritative surface (in which case
      # nothing is recorded).
      #
      # @param session [Hash] Rack session; persisted keys and values are strings
      # @param env [Hash] Rack env, for {Onetime::Session::Surface.for_env}
      # @param account_id [Integer] the account whose credentials were verified
      # @param methods [Array<String>] the ordered list of completed factors
      #   as observed by the caller (e.g. Rodauth's `authenticated_by`)
      # @param now [Time] override for the recorded timestamp (test seam)
      # @return [Hash, nil] the frozen payload actually stored, or nil
      def record(session, env, account_id:, methods:, now: Time.now)
        surface           = Session::Surface.for_env(env)
        completed_methods = Array(methods).map(&:to_s).freeze
        return nil if surface.nil?
        return nil if account_id.nil?
        return nil unless LOCAL_PRIMARIES.include?(completed_methods.first)

        payload      = {
          'account_id' => Integer(account_id),
          'at' => now.utc.to_i,
          'surface' => surface,
          'methods' => completed_methods,
        }.freeze

        session.delete(KEY) if session.respond_to?(:delete)
        return nil unless Session::Sidecar.write(session_id(session), KEY, payload)

        payload
      rescue StandardError
        nil
      end

      # The one-shot gate. Atomically consumes the proof, then returns true iff
      # it is for this account and surface and is not older than `max_age`.
      # Invalid proofs remain consumed so repeated attempts cannot replay them.
      #
      # @param session [Hash, nil] Rack session
      # @param env [Hash, nil] Rack env
      # @param account_id [Integer] the account the caller is about to
      #   bind an identity for
      # @param max_age [Integer] the maximum age of the proof in seconds
      # @param now [Time] clock override (test seam)
      # @return [Boolean]
      def satisfied?(session, env, account_id:, max_age:, now: Time.now)
        return false if session.nil? || env.nil?
        return false if account_id.nil?

        session.delete(KEY) if session.respond_to?(:delete)
        stored = Session::Sidecar.consume(session_id(session), KEY)
        return false unless stored.is_a?(Hash)

        stored_account = stored['account_id']
        return false unless stored_account == Integer(account_id)

        current_surface = Session::Surface.for_env(env)
        return false if current_surface.nil?
        return false unless stored['surface'] == current_surface

        methods = stored['methods']
        return false unless methods.is_a?(Array)
        return false unless LOCAL_PRIMARIES.include?(methods.first)

        at = stored['at']
        return false unless at.is_a?(Integer)
        return false if now.utc.to_i - at > Integer(max_age)
        return false if at > now.utc.to_i # future-dated proof is bogus

        true
      rescue StandardError
        false
      end

      # Read the stored payload without comparison. Callers that need to
      # log the proof or expose it in diagnostics use this; enforcement
      # uses {satisfied?}.
      def recorded(session)
        Session::Sidecar.read(session_id(session), KEY)
      rescue StandardError
        nil
      end

      # Clear the marker. Called from logout and any code path that
      # invalidates the proof (e.g. successful identity binding when the
      # proof is single-use).
      def clear(session)
        session.delete(KEY) if session.respond_to?(:delete)
        Session::Sidecar.delete(session_id(session), KEY)
      rescue StandardError
        0
      end

      private

      def session_id(session)
        session&.id&.public_id
      rescue StandardError
        nil
      end
    end
  end
end
