# lib/onetime/session/sidecar.rb
#
# frozen_string_literal: true

require 'familia'

require_relative 'codec'

module Onetime
  # Per-value session storage with independent TTLs (issue #3858).
  #
  # The session blob at `session:<sid>` is one encrypted value with one TTL, so
  # every field in it lives exactly as long as the session does. Some session
  # state wants a SHORTER lifetime than the session itself (an MFA completion
  # window, a UI context hint, a one-shot nonce). Redis TTLs are per-key, not
  # per-hash-field, so independent lifetimes require one Redis key per
  # (sid, field): the sibling STRING key `session:<sid>:<field>`.
  #
  # This module is that primitive. A closed registry ({FIELDS}) declares which
  # session fields may be externalized and under what policy. Registered
  # `externalize: true` fields are handled transparently by the Rack store
  # ({Onetime::Session}): {#commit} strips them out of the blob at write time
  # and stores them as sibling keys; {#merge} overlays them back into the
  # session hash at read time. Existing call sites (`sess['awaiting_mfa'] =
  # true`, `sess.delete('awaiting_mfa')`) do not change. The explicit API
  # ({#write}/{#read}/{#consume}/{#delete}/{#purge}) exists for cleanup
  # surfaces, ops, and explicit-use fields.
  #
  # ## Failure posture
  #
  # Best-effort, like the two existing sidecars (SessionMetadata via
  # TrackMetadata; the colonel entitlement-preview SETs): a sidecar failure
  # must never fail the session write — {Onetime::Session}'s outer rescue
  # returns false, which Rack reads as "not persisted" and may drop the
  # cookie. The middleware therefore wraps every hook in its own rescue.
  #
  # ## The admission rule (the security contract)
  #
  # Best-effort storage is only safe for a field whose ABSENCE IS THE SAFE
  # STATE: if a sidecar write is lost or the key expires early, the session
  # must degrade to a state that grants nothing. See the registry comment.
  #
  # ## Why a plain module, not a Familia model
  #
  # A Horreum is one backing hash with one default_expiration for the whole
  # record — the exact shape this primitive exists to escape. And a raw
  # `SET key payload EX ttl` is atomic (no SET-then-EXPIRE gap), which
  # Familia::StringKey's two-step set + update_expiration would reintroduce.
  module SessionSidecar
    extend self

    # Same format Session#valid_session_id? enforces. Every mutator is gated on
    # it, which guarantees two things at once: (1) every key this module ever
    # creates matches the Store scan-exclusion pattern (SIDECAR_KEY_PATTERN),
    # and (2) a sid can never inject `:`-delimited segments into the keyspace.
    SID_FORMAT = /\A[a-f0-9]{64,}\z/

    # Fallback TTL ceiling when neither the blob nor the config can provide one
    # (matches the session middleware's DEFAULT_OPTIONS expire_after).
    DEFAULT_TTL_CEILING = 86_400

    # The field registry — the SINGLE list of session fields that may live as
    # sidecar keys. Policy per field:
    #
    #   ttl           — default lifetime in seconds (always clamped, see
    #                   #effective_ttl: a sidecar key must never outlive the
    #                   session blob)
    #   encrypted     — codec-wrapped envelope (AES-256-GCM + HMAC via
    #                   Onetime::SessionCodec, sid/field-bound) vs plaintext
    #                   JSON envelope
    #   merge_on_read — overlaid into the session hash by find_session
    #   externalize   — write_session strips it from the blob and owns the
    #                   sidecar key (false = declared/policy-reviewed but still
    #                   blob-resident, or explicit-use only)
    #
    # ADMISSION RULE (the security contract): a field may set externalize: true
    # ONLY if its absence is the safe state. awaiting_mfa qualifies: with it
    # absent, the session is still blocked by the `authenticated == true` gate
    # (BaseSessionAuthStrategy); the M-11 awaiting_mfa guard is defense-in-
    # depth. Fields whose absence GRANTS anything — authenticated, external_id,
    # role — are permanently ineligible. So is authenticated_at: a forged or
    # vanished watermark would evade credential-watermark revocation (#3810),
    # which fails the rule in the other direction (absence must not be able to
    # LOOSEN anything either).
    #
    # EXPLICIT-USE FIELDS (merge_on_read: false, externalize: false) are never
    # touched by merge/commit; they work only through the explicit
    # write/read/consume/delete API — but they ARE included in purge, because
    # the registry is the cleanup contract (see below). Issue #3859 will
    # register `sso_connect_intent` (a single-use SSO connect nonce, consumed
    # via #consume) as such a field; it is not registered here because its
    # writers live on an unmerged branch.
    #
    # OUTSIDE THIS PRIMITIVE, by design: `session_metadata:<sid>`
    # (TrackMetadata / Onetime::SessionMetadata) keeps its own 30-day TTL,
    # which deliberately EXCEEDS the blob TTL for audit purposes — that
    # intentionally violates this primitive's never-outlive-the-blob clamp
    # invariant, so it must never become a registry entry.
    #
    # UNREGISTERED FIELDS ARE REJECTED with ArgumentError. The registry IS the
    # cleanup contract: purge deletes exactly the registry's key names with no
    # SCAN, and the Store scan exclusion is only justifiable because every
    # sidecar key is enumerable. A permissive default would silently accumulate
    # keys no deletion path knows about (the exact orphan pattern the
    # entitlement-preview keys already exhibit). Fail-fast at write time is a
    # developer-facing error, not a runtime hazard: writes come from app code,
    # never from user input.
    FIELDS = {
      # 15-minute MFA completion window instead of riding the 24h blob — the
      # point of #3858 for this field. Expiry strands a half-done MFA login as
      # unauthenticated (user restarts login): fail-closed.
      'awaiting_mfa'   => { ttl: 900,   encrypted: true,  merge_on_read: true, externalize: true  },
      # Post-AddDomain UI context; cosmetic on expiry. Same value is plaintext
      # in CustomDomain records, so a plaintext envelope leaks nothing new.
      'domain_context' => { ttl: 3_600, encrypted: false, merge_on_read: true, externalize: true  },
      # One-shot Roda flash messages (may embed email addresses — mild PII,
      # hence encrypted). Declared but NOT externalized: the Roda flash plugin
      # writes it mid-request via its own delete-then-rewrite cycle, which must
      # be audited against commit semantics before flipping this on.
      '_flash'         => { ttl: 600,   encrypted: true,  merge_on_read: true, externalize: false },
    }.freeze

    # Deterministic sibling-key derivation — no stored key names needed, which
    # is what makes purge an exact O(registry) DEL. Callers are responsible for
    # sid format (every public mutator here guards it); the field must be
    # registered.
    #
    # @return [String] "session:<sid>:<field>"
    def key_for(sid, field)
      field = field.to_s
      ensure_registered!(field)
      "session:#{sid}:#{field}"
    end

    # Store one field value under its own key + TTL. The TTL is always clamped
    # so the key can never outlive the session blob (see #effective_ttl), and
    # the write is a single SET+EX — atomic, no SET-then-EXPIRE gap for a
    # crash to leave an immortal key in.
    #
    # @return [Integer, nil] the effective (clamped) TTL, or nil for a sid
    #   that fails the format guard (no key is ever created for one).
    def write(sid, field, value, ttl: nil, dbclient: nil, codec: nil)
      field  = field.to_s
      policy = ensure_registered!(field)
      return nil unless valid_sid?(sid)

      db      = dbclient || Familia.dbclient
      seconds = effective_ttl(sid, ttl || policy[:ttl], db)
      db.set(key_for(sid, field), encode_envelope(sid, field, value, policy, codec), ex: seconds)
      seconds
    end

    # Read one field value. Returns nil for absent/expired keys AND for any
    # value that fails authentication — tampered ciphertext, unparseable
    # envelope, or a sid/field binding mismatch — so a forged or replayed
    # sidecar value is indistinguishable from no value at all.
    #
    # @return [Object, nil]
    def read(sid, field, dbclient: nil, codec: nil)
      field  = field.to_s
      policy = ensure_registered!(field)
      return nil unless valid_sid?(sid)

      db = dbclient || Familia.dbclient
      decode_envelope(sid, field, db.get(key_for(sid, field)), policy, codec)
    end

    # Atomically read AND delete one field value — for single-use nonces
    # (issue #3859, the SSO connect-intent) where a read-then-delete pair
    # would race: two concurrent presenters of the same nonce must never both
    # see it. Single GETDEL when the client supports it; otherwise GET+DEL in
    # one MULTI/EXEC transaction (concurrent transactions serialize, so at
    # most one caller observes the value either way). Decodes and verifies
    # exactly like #read.
    #
    # @return [Object, nil] the consumed value, or nil (absent/expired/
    #   tampered/binding-mismatch).
    def consume(sid, field, dbclient: nil, codec: nil)
      field  = field.to_s
      policy = ensure_registered!(field)
      return nil unless valid_sid?(sid)

      db  = dbclient || Familia.dbclient
      key = key_for(sid, field)
      raw = if db.respond_to?(:getdel)
              db.getdel(key)
            else
              db.multi do |tx|
                tx.get(key)
                tx.del(key)
              end&.first
            end
      decode_envelope(sid, field, raw, policy, codec)
    end

    # @return [Boolean] whether the field's key currently exists.
    def exists?(sid, field, dbclient: nil)
      field = field.to_s
      ensure_registered!(field)
      return false unless valid_sid?(sid)

      db = dbclient || Familia.dbclient
      db.exists(key_for(sid, field)).to_i.positive?
    end

    # Delete one field's key.
    #
    # @return [Integer] number of keys removed (0 or 1).
    def delete(sid, field, dbclient: nil)
      field = field.to_s
      ensure_registered!(field)
      return 0 unless valid_sid?(sid)

      db = dbclient || Familia.dbclient
      db.del(key_for(sid, field))
    end

    # Delete EVERY registry field's key for this sid in one DEL by exact name —
    # no SCAN, O(registry), callable from any surface that has a sid. This is
    # the property the closed registry buys (and the one the entitlement-
    # preview keys lack: nothing deletes those on logout; they only expire).
    # Includes explicit-use fields: cleanup covers the whole registry.
    #
    # @return [Integer] number of keys removed.
    def purge(sid, dbclient: nil)
      return 0 unless valid_sid?(sid)

      db = dbclient || Familia.dbclient
      db.del(*FIELDS.keys.map { |field| key_for(sid, field) })
    end
    alias delete_all purge

    # Read-side middleware hook (used only by Onetime::Session#find_session):
    # overlay every merge_on_read+externalize field onto the freshly-decoded
    # session hash, in one pipeline. The sidecar value WINS over a blob-
    # resident copy — rolling-deploy back-compat: a pre-deploy blob still
    # carrying an externalized field keeps working, and the field moves out of
    # the blob on its next commit.
    #
    # NOT called on the blob-miss or tamper/new-sid paths: a revoked/expired
    # session must present as {}; its sidecar keys are inert until purged or
    # TTL-expired.
    #
    # @return [Hash] { data: <possibly-overlaid hash>, fields: <overlaid field
    #   names> } — :fields feeds the write-side deletion semantics (#commit).
    def merge(sid, session_data, dbclient: nil, codec: nil)
      overlay = FIELDS.select { |_f, p| p[:merge_on_read] && p[:externalize] }.keys
      return { data: session_data, fields: [] } if overlay.empty? || !valid_sid?(sid)

      db   = dbclient || Familia.dbclient
      raws = db.pipelined do |pipe|
        overlay.each { |field| pipe.get(key_for(sid, field)) }
      end

      data   = session_data
      merged = []
      overlay.each_with_index do |field, idx|
        value = decode_envelope(sid, field, raws[idx], FIELDS[field], codec)
        # nil means absent/expired/unauthentic — nothing to overlay. (A stored
        # nil never exists: commit turns a nil-valued field into a DEL.)
        next if value.nil?

        data        = data.dup if data.equal?(session_data)
        data[field] = value
        merged << field
      end

      { data: data, fields: merged }
    end

    # Write-side middleware hook (used only by Onetime::Session#write_session,
    # BEFORE blob serialization): externalize every registered field out of the
    # session hash. Per externalize field:
    #
    #   present, non-nil       -> SET envelope EX clamped-ttl (refreshed every
    #                             commit, tracking the blob's per-request TTL
    #                             refresh); field removed from the hash copy
    #   present, nil           -> DEL; field removed from the hash copy
    #   absent, but in merged: -> DEL (the app deleted a field the read-side
    #                             overlaid this request — e.g. SyncSession
    #                             clearing awaiting_mfa)
    #   absent, not merged     -> no-op
    #
    # Returns the (possibly slimmed) hash to serialize; on the fast path — no
    # registered field present, nothing merged — it returns the input hash
    # untouched with ZERO Redis commands, so the dominant anonymous/CSRF-only
    # session pays nothing. The caller's own rescue preserves the original
    # hash on failure: fields stay in the blob for this cycle (data safe; only
    # the independent TTL degrades to the blob's).
    #
    # `ceiling:` (optional) replaces the CONFIG-DERIVED fallback ceiling used
    # when the blob key does not exist yet (first commit runs just before the
    # blob SET) or carries no TTL — the middleware passes its own
    # `@expire_after` so its value wins over global config. A live blob's
    # REMAINING TTL, when present, still wins as the ceiling regardless.
    #
    # @return [Hash]
    def commit(sid, session_data, merged: nil, dbclient: nil, codec: nil, ceiling: nil)
      return session_data unless valid_sid?(sid)

      merged  = Array(merged).map(&:to_s)
      writes  = {}
      deletes = []
      data    = session_data

      FIELDS.each do |field, policy|
        next unless policy[:externalize]

        if data.key?(field)
          value = data[field]
          if value.nil?
            deletes << field
          else
            # Envelopes are encoded before the pipeline opens so a codec
            # failure aborts cleanly with no partial writes queued.
            writes[field] = encode_envelope(sid, field, value, policy, codec)
          end
          data = data.dup if data.equal?(session_data)
          data.delete(field)
        elsif merged.include?(field)
          deletes << field
        end
      end

      return data if writes.empty? && deletes.empty?

      db = dbclient || Familia.dbclient
      # One TTL probe per commit (not per field): every field clamps against
      # the same blob ceiling read once, before the pipeline.
      effective_ceiling = writes.empty? ? nil : ttl_ceiling(sid, db, fallback: ceiling)
      db.pipelined do |pipe|
        writes.each do |field, payload|
          pipe.set(key_for(sid, field), payload, ex: clamp_ttl(FIELDS[field][:ttl], effective_ceiling))
        end
        deletes.each { |field| pipe.del(key_for(sid, field)) }
      end

      data
    end

    private

    def valid_sid?(sid)
      sid.is_a?(String) && sid.match?(SID_FORMAT)
    end

    # Registry gate: unregistered fields fail fast (see the FIELDS comment for
    # why a permissive default is the wrong kind of forgiving).
    def ensure_registered!(field)
      policy = FIELDS[field]
      return policy if policy

      raise ArgumentError, "unregistered session sidecar field: #{field.inspect}"
    end

    # INVARIANT: a sidecar key must never outlive the session blob. Clamp the
    # requested TTL to the blob's REMAINING TTL, so a revoked/expiring blob's
    # sidecars die no later than the blob would have. With no blob (mid-first-
    # request: commit runs just before the blob SET) or a TTL-less blob
    # (expire_after disabled), fall back to the caller-supplied ceiling when
    # given (the middleware's own expire_after), else the configured ceiling —
    # either way, the TTL the blob is about to get.
    def effective_ttl(sid, requested, dbclient, ceiling: nil)
      clamp_ttl(requested, ttl_ceiling(sid, dbclient, fallback: ceiling))
    end

    def ttl_ceiling(sid, dbclient, fallback: nil)
      blob_ttl = dbclient.ttl("session:#{sid}") # -2 no key, -1 no TTL
      return blob_ttl if blob_ttl >= 1

      return fallback.to_i if fallback.to_i.positive?

      configured = Onetime.respond_to?(:session_config) ? Onetime.session_config['expire_after'].to_i : 0
      configured.positive? ? configured : DEFAULT_TTL_CEILING
    end

    def clamp_ttl(requested, ceiling)
      [requested.to_i, ceiling].min.clamp(1, ceiling)
    end

    # Envelopes are JSON both ways so values round-trip with their types
    # (false/nil/hashes), which a bare string value would flatten.
    #
    # encrypted: the canonical SessionCodec blob format wrapped around
    # {'sid','f','v'}. The sid/field binding prevents replaying one session's
    # sidecar value under another sid or field — a property the session blob
    # itself does not have, so sidecar posture is strictly >= blob posture.
    # (Deletion remains undetectable, same as blob deletion.)
    #
    # plaintext: {'v' => value} — same plaintext-in-Redis class as
    # SessionMetadata fields and the entitlement-preview SETs.
    def encode_envelope(sid, field, value, policy, codec)
      if policy[:encrypted]
        codec ||= Onetime::SessionCodec.from_config
        raise 'session codec unavailable for encrypted sidecar field' unless codec

        codec.encode({ 'sid' => sid, 'f' => field, 'v' => value })
      else
        Familia::JsonSerializer.dump({ 'v' => value })
      end
    end

    # nil for anything that is not an authentic envelope for THIS (sid, field):
    # codec.decode never raises (tampered -> nil), and a decoded envelope whose
    # binding does not match is treated as absent, never as an error.
    def decode_envelope(sid, field, raw, policy, codec)
      return nil if raw.nil?

      if policy[:encrypted]
        codec ||= Onetime::SessionCodec.from_config
        return nil unless codec

        envelope = codec.decode(raw)
        return nil unless envelope.is_a?(Hash) && envelope['sid'] == sid && envelope['f'] == field

        envelope['v']
      else
        envelope = begin
          Familia::JsonSerializer.parse(raw)
        rescue StandardError
          nil
        end
        envelope.is_a?(Hash) ? envelope['v'] : nil
      end
    end
  end
end
