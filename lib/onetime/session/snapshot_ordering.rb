# lib/onetime/session/snapshot_ordering.rb
#
# frozen_string_literal: true

require 'openssl'

require_relative 'namespace'
require_relative 'sidecar'

module Onetime
  # Allocates bootstrap snapshot ordering fields (ADR-046). The opaque epoch
  # identifies a session-ID lifetime; the version is a positive canonical
  # decimal string within it. The client decides whether to accept a snapshot.
  # `snapshot_generated_at` is for age and diagnostics, never for ordering.
  module Session::SnapshotOrdering
    extend self

    # Rack env key holding this request's allocation:
    #   { epoch:, version:, generated_at: }   allocated
    #   { error: <exception class name> }     allocation failed
    #   absent                                session not ordered (or not a
    #                                         Web Core request)
    ENV_KEY = 'onetime.snapshot_ordering'

    FIELD = 'snapshot_version'

    # 128 bits, the same truncation Onetime::SessionMetadata.handle_for uses.
    EPOCH_LENGTH = 32

    # Domain separation: the epoch must not equal, or be derivable from, any
    # other keyed digest of the same sid — in particular the colonel-facing
    # revoke handle (SessionMetadata::HANDLE_DOMAIN), which the revoke
    # endpoint accepts as an identifier. The epoch is published to the tab and
    # recorded in diagnostics; the handle must not become guessable from it.
    EPOCH_DOMAIN = 'bootstrap-snapshot-epoch:v1'

    # Fixed-width UTC RFC 3339 with exactly six fractional digits.
    GENERATED_AT_FORMAT = '%Y-%m-%dT%H:%M:%S.%6NZ'

    # A session is ordered when its loaded state marks it authenticated or
    # awaiting MFA: those are the sessions whose tabs refresh. `awaiting_mfa`
    # is sidecar-backed and already merged into the loaded hash. Anonymous
    # sessions are most of the traffic and have no stream to order; they cost
    # no Redis command here.
    #
    # Deliberately the RAW session flags, not the evaluator's verdict:
    # allocation runs ahead of the authentication strategy (the version is a
    # start stamp), and a session the evaluator goes on to reject still
    # answers through a payload that reports no session, which the client
    # never subjects to ordering.
    def ordered?(session)
      return false unless session.respond_to?(:[])

      session['authenticated'] == true || session['awaiting_mfa'] == true
    end

    # Stable and opaque per session id; a renewed session id is a new epoch
    # with no migration state. The raw sid never enters a payload or a log.
    #
    # @param sid [String] the plain session id
    # @return [String] 32 lowercase hex characters
    def epoch_for(sid)
      digest = OpenSSL::Digest.new('sha256')
      OpenSSL::HMAC.hexdigest(digest, OT.global_secret.to_s, "#{EPOCH_DOMAIN}:#{sid}")[0, EPOCH_LENGTH]
    end

    # Allocate the pair for one request. Raises on any failure (a Redis
    # error, a session id that fails the sidecar format guard): the caller
    # records it, and no payload is ever labelled ordered without a version.
    #
    # @param session [Rack::Session::Abstract::SessionHash]
    # @param ttl [Integer, nil] the session's authoritative lifetime
    # @return [Hash] { epoch:, version:, generated_at: }
    def allocate(session, ttl: nil)
      sid     = session_id(session)
      version = Session::Sidecar.allocate_counter(sid, FIELD, ttl: ttl)

      {
        epoch: epoch_for(sid),
        version: version,
        generated_at: Time.now.utc.strftime(GENERATED_AT_FORMAT),
      }
    end

    private

    def session_id(session)
      id = session.respond_to?(:id) ? session.id : nil
      id.respond_to?(:public_id) ? id.public_id : id
    end
  end
end
