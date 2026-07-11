# lib/onetime/session.rb
#
# frozen_string_literal: true

require 'rack/session/abstract/id'
require 'securerandom'

require 'base64'
require 'openssl'
require 'familia'

require_relative 'logger_methods'
require_relative 'session/codec'
require_relative 'operations/sessions/track_metadata'

module Onetime
  # Onetime::Session - A secure Rack session store using Familia's StringKey DataType
  #
  # This implementation provides secure session storage with AES-256-GCM encryption
  # and HMAC verification using Familia's Redis-backed StringKey data type.
  #
  # SECURITY MODEL:
  # ===============
  # - Session ID: Plain 64-char hex string (visible in cookie and Redis key)
  #   Example: "c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655"
  #
  # - Session Data: JSON serialized, AES-256-GCM encrypted, Base64 encoded, HMAC signed
  #   Format: "base64(iv:auth_tag:ciphertext)--hmac"
  #   Example: "eyJhY2NvdW50X2lkIjoxMjN9...--a3f5e8d9c2b1..."
  #
  # - Secret: Used to derive two keys:
  #   * HMAC key: Signs session data to prevent tampering
  #   * Encryption key: AES-256-GCM key for session data confidentiality
  #
  # WHAT THE SECRET PROTECTS:
  # =========================
  # ✅ Session data integrity - Can't modify contents without detection
  # ✅ Prevents tampering - Can't change account_id from 123 to 456
  # ✅ Session data confidentiality - Encrypted at rest in Redis
  # ❌ Does NOT hide session ID - The ID itself is visible in cookie
  #
  # STORAGE LAYOUT:
  # ==============
  # Browser Cookie: onetime.session=c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655
  # Redis Key:      session:c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655
  # Redis Value:    base64(iv:auth_tag:ciphertext)--hmac_signature
  #                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^  ^^^^^^^^^^^^^
  #                 Base64(AES-GCM(JSON(session_data))) HMAC signature
  #
  # Usage:
  #   use Onetime::Session,
  #     key: 'onetime.session',
  #     secret: ENV.fetch('SESSION_SECRET') { raise "SESSION_SECRET not set" },
  #     expire_after: 3600*24,  # 24 hours
  #     secure: true,  # HTTPS only
  #
  # @see https://raw.githubusercontent.com/rack/rack-session/dadcfe60f193e8/lib/rack/session/abstract/id.rb
  # @see https://raw.githubusercontent.com/rack/rack-session/dadcfe60f193e8/lib/rack/session/encryptor.rb
  class Session < Rack::Session::Abstract::PersistedSecure
    include Onetime::LoggerMethods

    unless defined?(DEFAULT_OPTIONS)
      DEFAULT_OPTIONS = {
        key: 'onetime.session',
        expire_after: 86_400, # 24 hours default
        namespace: 'session',
        sidbits: 256,  # Required by Rack::Session::Abstract::Persisted
        dbclient: nil,
      }.freeze
    end

    attr_reader :dbclient

    def initialize(app, options = {})
      # Require a secret for security - fall back to site secret if not set
      is_valid_string = options[:secret].is_a?(String) && !options[:secret].empty?
      unless is_valid_string
        site_secret = OT.conf.dig('site', 'secret')
        raise ArgumentError, 'SESSION_SECRET is not set and no site secret available' unless site_secret.is_a?(String) && !site_secret.empty?

        options[:secret] = site_secret
        OT.ld '[Session] SESSION_SECRET not set, using site secret for session signing'

      end

      # Merge options with defaults
      # Note: :key sets the cookie name (defaults to 'onetime.session' instead of
      # Rack's default 'rack.session' to prevent session fixation attacks), while
      # the Rack environment key for session data is always env['rack.session'].
      options = DEFAULT_OPTIONS.merge(options)

      # Configure Familia connection if redis_uri provided
      @dbclient = options[:dbclient] || Familia.dbclient # TODO: options.delete(:dbclient)?

      # Call parent to set @app, @default_options, @key, etc. Must happen after
      # we prepare options but before we read from them to derive the keys. Otherwise
      # it's an, "Ow, I fell on my keys" type situation.
      super

      @secret       = options[:secret]
      @expire_after = options[:expire_after]
      @namespace    = options[:namespace] || 'session'

      # All crypto (HKDF subkey derivation, AES-256-GCM, HMAC, the at-rest
      # `base64(...)--hmac` format) lives in the canonical Codec, shared with the
      # session admin read verbs so encoder and decoder can never drift. The ivar
      # is kept for parity with callers/tests that read the raw AES key directly.
      @codec              = SessionCodec.new(@secret)
      @encryption_key_raw = @codec.encryption_key_raw
    end

    private

    # Create a StringKey instance for a session ID
    #
    # This creates a Familia::StringKey that maps to:
    # Redis Key: session:c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655
    #
    # The session ID is NOT encrypted - it's the same value in the cookie
    def get_stringkey(sid)
      return nil unless sid

      key = Familia.join(@namespace, sid)
      Familia::StringKey.new(
        key,
        default_expiration: @expire_after,
        default: nil,
      )
    end

    def delete_session(_request, sid, _options)
      # Extract string ID from SessionId object if needed
      sid_string = sid.respond_to?(:public_id) ? sid.public_id : sid

      session_logger.info 'Session deletion initiated',
        {
          session_id: sid_string,
          operation: 'delete',
        }

      if stringkey = get_stringkey(sid_string)
        result = stringkey.del
        session_logger.trace 'Session deleted from Redis',
          {
            session_id: sid_string,
            redis_key: stringkey.dbkey,
            deleted: result,
            operation: 'delete',
          }

      else
        session_logger.trace 'No session found to delete',
          {
            session_id: sid_string,
            operation: 'delete',
          }

      end

      new_sid = generate_sid
      session_logger.trace 'New session generated after deletion',
        {
          session_id: new_sid.respond_to?(:public_id) ? new_sid.public_id : new_sid,
          operation: 'delete',
        }

      new_sid
    end

    # Validates session ID format
    #
    # Session IDs are plain hex strings (not encrypted):
    # - Must be 64+ hexadecimal characters
    # - Example: "c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655"
    #
    # This is just format validation - doesn't check if session exists in Redis
    def valid_session_id?(sid)
      return false if sid.to_s.empty?
      return false unless sid.match?(/\A[a-f0-9]{64,}\z/)

      # Additional security checks could go here
      true
    end

    # Verifies HMAC signature to detect tampering
    #
    # SECURITY: Uses constant-time comparison to prevent timing attacks
    #
    # This ensures the session data hasn't been modified since it was written.
    # If someone tries to change Redis value from {"account_id":123} to
    # {"account_id":456}, the HMAC won't match and session will be rejected.
    # Delegates to the canonical {Codec}. Kept as a named method for parity with
    # the session tryout and any caller that verified HMAC directly.
    def valid_hmac?(data, hmac)
      @codec.valid_hmac?(data, hmac)
    end

    # Derives purpose-specific keys from the session master secret using HKDF
    # (RFC 5869). Delegates to the {Codec} so there is one derivation of record.
    def derive_key(purpose)
      @codec.derive_key(purpose)
    end

    # Computes the HMAC signature for session data (delegates to {Codec}).
    def compute_hmac(data)
      @codec.compute_hmac(data)
    end

    # Encrypts session data using AES-256-GCM (delegates to {Codec}).
    # Output: `iv[12] + auth_tag[16] + ciphertext` (binary).
    def encrypt_data(plaintext)
      @codec.encrypt_data(plaintext)
    end

    # Decrypts AES-256-GCM session data (delegates to {Codec}). Returns the
    # plaintext JSON string, or nil on a short/tampered/undecryptable value.
    def decrypt_data(encrypted_data)
      @codec.decrypt_data(encrypted_data)
    end

    # READ SESSION FROM REDIS
    # =======================
    #
    # Flow:
    # 1. Extract session ID from cookie (plain text hex string)
    # 2. Validate ID format
    # 3. Load data from Redis: session:SESSION_ID
    # 4. Verify HMAC signature
    # 5. Decode Base64 to get encrypted binary data
    # 6. Decrypt AES-256-GCM encrypted data
    # 7. Parse JSON and return session data hash
    #
    # RODAUTH LOGIN FAILURE EXAMPLE:
    # ==============================
    #
    # When Rodauth checks if user is logged in:
    #   logged_in? => session_value => env['rack.session'][:account_id]
    #
    # Login fails ("Please login to continue") if:
    #
    # 1. Wrong cookie name in request:
    #    Cookie: session=abc123  ❌ (should be onetime.session=abc123)
    #
    # 2. Invalid session ID format:
    #    Cookie: onetime.session=invalid  ❌ (must be 64+ hex chars)
    #
    # 3. Session ID doesn't exist in Redis:
    #    Redis GET session:abc123 => nil  ❌ (expired or never created)
    #
    # 4. HMAC verification fails:
    #    Redis value: "data--wrong_hmac"  ❌ (data was tampered with)
    #    Result: Returns empty session {} instead of {account_id: 123}
    #
    # 5. Session data missing account_id:
    #    Redis value valid, but JSON is {}  ❌ (session exists but not logged in)
    #
    # In all failure cases, env['rack.session'][:account_id] is nil/missing,
    # so Rodauth's logged_in? returns false.
    def find_session(_request, sid)
      # Parent class already extracts sid from cookies
      # sid may be a SessionId object or nil
      sid_string = sid.respond_to?(:public_id) ? sid.public_id : sid

      session_logger.trace 'Session lookup initiated',
        {
          session_id: sid_string,
          sid_type: sid.class.name,
          operation: 'read',
        }

      # Only generate new sid if none provided or invalid
      unless sid_string && valid_session_id?(sid_string)
        session_logger.trace 'Session ID invalid or missing',
          {
            session_id: sid_string,
            valid: false,
            operation: 'read',
          }

        new_sid = generate_sid
        session_logger.trace 'New session created',
          {
            session_id: new_sid.respond_to?(:public_id) ? new_sid.public_id : new_sid,
            operation: 'read',
          }

        return [new_sid, {}]
      end

      begin
        # Load from Redis using session ID
        # Key format: session:c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655
        stringkey   = get_stringkey(sid_string)
        stored_data = stringkey.value if stringkey

        session_logger.trace 'Redis lookup complete',
          {
            session_id: sid_string,
            has_data: !stored_data.nil?,
            data_size: stored_data&.bytesize,
            ttl: stringkey&.ttl,
            operation: 'read',
          }

        # If no data stored, return empty session
        # This happens when session expired or was never created
        unless stored_data
          session_logger.trace 'No session data found',
            {
              session_id: sid_string,
              operation: 'read',
            }

          return [sid, {}]  # Empty session - Rodauth sees this as "not logged in"
        end

        # Split stored data into base64 data and HMAC signature
        # Format: "eyJhY2NvdW50X2lkIjoxMjN9...--a3f5e8d9c2b1..."
        data, hmac = stored_data.split('--', 2)

        session_logger.trace 'HMAC verification',
          {
            session_id: sid_string,
            has_hmac: !hmac.nil?,
            data_length: data&.length,
            hmac_length: hmac&.length,
            operation: 'read',
          }

        # Verify HMAC to detect tampering
        # If someone modified Redis value, HMAC won't match
        unless hmac && valid_hmac?(data, hmac)
          session_logger.warn 'Session HMAC verification failed',
            {
              session_id: sid_string,
              has_hmac: !hmac.nil?,
              operation: 'read',
            }

          # Session tampered with - create new session
          new_sid = generate_sid
          return [new_sid, {}]  # Empty session - Rodauth sees "not logged in"
        end

        # Decode Base64 to get encrypted binary data
        encrypted_data = Base64.strict_decode64(data)
        session_logger.trace 'Base64 decode complete',
          {
            session_id: sid_string,
            encrypted_size: encrypted_data.bytesize,
            operation: 'read',
          }

        # Decrypt AES-256-GCM encrypted data
        decrypted_data = decrypt_data(encrypted_data)
        unless decrypted_data
          session_logger.warn 'Session decryption failed',
            {
              session_id: sid_string,
              operation: 'read',
            }
          new_sid = generate_sid
          return [new_sid, {}]
        end

        session_logger.trace 'AES-256-GCM decryption complete',
          {
            session_id: sid_string,
            decrypted_size: decrypted_data.bytesize,
            operation: 'read',
          }

        # Parse JSON to get session hash
        # Example: {"account_id":123,"awaiting_mfa":true}
        session_data = Familia::JsonSerializer.parse(decrypted_data)

        session_logger.trace 'Session loaded successfully',
          {
            session_id: sid_string,
            session_keys: session_data.keys,
            account_id: session_data['account_id'],
            external_id: session_data['external_id'],
            authenticated_at: session_data['authenticated_at'],
            awaiting_mfa: session_data['awaiting_mfa'],
            two_factor_auth_setup: session_data['two_factor_auth_setup'],
            operation: 'read',
          }

        # Return session data - this becomes env['rack.session']
        # Rodauth checks env['rack.session'][:account_id] to verify login
        [sid, session_data]
      rescue StandardError => ex
        # Log error with structured context
        session_logger.error 'Error reading session',
          {
            session_id: sid_string,
            error: ex.message,
            error_class: ex.class.name,
            backtrace: ex.backtrace&.first(5),
            operation: 'read',
          }

        # Return new session on any error
        # This also causes Rodauth to see "not logged in"
        [generate_sid, {}]
      end
    end

    # WRITE SESSION TO REDIS
    # ======================
    #
    # Flow:
    # 1. Serialize session data to JSON
    #    {"account_id":123,"awaiting_mfa":true} => '{"account_id":123,...}'
    #
    # 2. Encrypt with AES-256-GCM (confidentiality at rest)
    #    => iv + auth_tag + ciphertext (binary)
    #
    # 3. Base64 encode (for safe storage of binary data)
    #    => "eyJhY2NvdW50X2lkIjoxMjN9..."
    #
    # 4. Compute HMAC signature (prevents tampering)
    #    => "a3f5e8d9c2b1..."
    #
    # 4. Combine with separator
    #    => "eyJhY2NvdW50X2lkIjoxMjN9...--a3f5e8d9c2b1..."
    #
    # 5. Store in Redis with TTL
    #    SET session:SESSION_ID "data--hmac" EX 86400
    #
    # 6. Cookie contains just the session ID (not encrypted)
    #    Set-Cookie: onetime.session=c9803eb...
    def write_session(request, sid, session_data, _options)
      # Extract string ID from SessionId object if needed
      sid_string = sid.respond_to?(:public_id) ? sid.public_id : sid

      session_logger.trace 'Session write initiated',
        {
          session_id: sid_string,
          session_keys: session_data&.keys,
          session_data_class: session_data.class.name,
          operation: 'write',
        }

      # Step 1: Serialize session data to JSON
      # Example: {"account_id":123,"awaiting_mfa":true}
      json_data = Familia::JsonSerializer.dump(session_data)
      session_logger.trace 'JSON serialization complete',
        {
          session_id: sid_string,
          json_size: json_data.bytesize,
          operation: 'write',
        }

      # Step 2: Encrypt with AES-256-GCM
      # Provides confidentiality at rest in Redis
      encrypted_data = encrypt_data(json_data)
      session_logger.trace 'AES-256-GCM encryption complete',
        {
          session_id: sid_string,
          encrypted_size: encrypted_data.bytesize,
          operation: 'write',
        }

      # Step 3: Base64 encode (for safe storage of binary encrypted data)
      encoded = Base64.strict_encode64(encrypted_data)
      session_logger.trace 'Base64 encoding complete',
        {
          session_id: sid_string,
          encoded_size: encoded.bytesize,
          operation: 'write',
        }

      # Step 3: Compute HMAC signature for integrity verification
      # This proves the data hasn't been modified
      hmac        = compute_hmac(encoded)
      signed_data = "#{encoded}--#{hmac}"

      session_logger.trace 'HMAC computation complete',
        {
          session_id: sid_string,
          hmac_length: hmac.length,
          signed_data_size: signed_data.bytesize,
          operation: 'write',
        }

      # Step 4: Get or create StringKey for this session
      stringkey = get_stringkey(sid_string)

      # Step 5: Save to Redis
      # Key: session:c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655
      # Value: eyJhY2NvdW50X2lkIjoxMjN9...--a3f5e8d9c2b1...
      stringkey.set(signed_data)
      session_logger.trace 'Redis SET complete',
        {
          session_id: sid_string,
          redis_key: stringkey.dbkey,
          operation: 'write',
        }

      # Step 6: Update expiration if configured
      if @expire_after && @expire_after > 0
        stringkey.update_expiration(expiration: @expire_after)
        session_logger.trace 'Expiration updated',
          {
            session_id: sid_string,
            expire_after: @expire_after,
            operation: 'write',
          }

      end

      # Best-effort per-customer session sidecar (spec 40; adaptation #2). This
      # is the ONLY request-path point where the plain sid and the post-login
      # session_data are both present, and it commits ~per request so the sidecar
      # refreshes last_activity naturally. Gated to authenticated sessions so
      # anonymous/CSRF-only writes skip it entirely.
      #
      # CRITICAL: wrapped in its OWN begin/rescue so a sidecar failure can NEVER
      # fall through to this method's outer rescue — that rescue returns `false`,
      # which Rack reads as "session not persisted" and may drop the cookie,
      # breaking auth for every request. The sidecar is a convenience index; it
      # must never be able to fail the session write.
      if session_data && session_data['authenticated'] && session_data['external_id']
        begin
          Onetime::Operations::Sessions::TrackMetadata.new(
            session_id: sid_string,
            session_data: session_data,
            env: request.respond_to?(:env) ? request.env : nil,
          ).call
        rescue StandardError => ex
          session_logger.error 'Session metadata sidecar failed (swallowed)',
            {
              session_id: sid_string,
              error: ex.message,
              error_class: ex.class.name,
              operation: 'write',
            }
        end
      end

      # Calculate session data metrics for logging
      data_size  = signed_data.bytesize
      ttl_value  = stringkey.ttl
      expires_at = ttl_value > 0 ? Time.now + ttl_value : nil

      # Structured trace logging with all critical session fields
      session_logger.trace 'Session saved successfully',
        {
          session_id: sid_string,
          session_keys: session_data&.keys,
          account_id: session_data&.fetch('account_id', 'n/a'),
          external_id: session_data&.fetch('external_id', 'n/a'),
          authenticated_at: session_data&.fetch('authenticated_at', 'n/a'),
          two_factor_auth_setup: session_data&.fetch('two_factor_auth_setup', 'n/a'),
          awaiting_mfa: session_data&.fetch('awaiting_mfa', 'n/a'),
          ttl: ttl_value,
          data_size: data_size,
          expires_at: expires_at,
          operation: 'write',
        }

      # Return the original sid (may be SessionId object)
      # The parent Rack middleware will set the cookie:
      # Set-Cookie: onetime.session=c9803eb... (just the session ID, not encrypted)
      sid
    rescue StandardError => ex
      # Log error with structured context
      session_logger.error 'Error writing session',
        {
          session_id: sid_string,
          session_keys: session_data&.keys,
          error: ex.message,
          error_class: ex.class.name,
          backtrace: ex.backtrace&.first(5),
          operation: 'write',
        }

      # Return false to indicate failure
      false
    end

    # Clean up expired sessions (optional, can be called periodically)
    # Note: Redis TTL handles this automatically, so manual cleanup isn't required
    def cleanup_expired_sessions
      # This would typically be handled by Redis TTL automatically
      # but you could implement manual cleanup if needed
    end
  end
end
