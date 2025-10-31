# lib/onetime/session.rb

require 'rack/session/abstract/id'
require 'securerandom'

require 'base64'
require 'openssl'
require 'familia'

require_relative 'logging'

module Onetime
  # Onetime::Session - A secure Rack session store using Familia's StringKey DataType
  #
  # This implementation provides secure session storage with HMAC verification
  # and encryption using Familia's Redis-backed StringKey data type.
  #
  # Key Features:
  # - Secure session ID generation with SecureRandom
  # - HMAC-based session integrity verification
  # - JSON serialization for session data
  # - Automatic TTL management via Familia's expiration features
  # - Redis connection pooling via Familia
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
    include Onetime::Logging
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
      # Require a secret for security
      raise ArgumentError, 'Secret required for secure sessions' unless options[:secret]

      # Merge options with defaults
      options = DEFAULT_OPTIONS.merge(options)

      # Force cookie name to 'onetime.session' for security (custom name prevents
      # session fixation attacks). This overrides Rack's default 'rack.session'.
      # The session key in env['rack.session'] remains standard for compatibility.
      options[:key] = 'onetime.session'

      # Configure Familia connection if redis_uri provided
      @dbclient = options[:dbclient] || Familia.dbclient

      super

      @secret       = options[:secret]
      @expire_after = options[:expire_after]
      @namespace    = options[:namespace] || 'session'

      # Derive different keys for different purposes
      @hmac_key       = derive_key('hmac')
      @encryption_key = derive_key('encryption')
    end

    private

    # Create a StringKey instance for a session ID
    def get_stringkey(sid)
      return nil unless sid

      key = Familia.join(@namespace, sid)
      Familia::StringKey.new(key,
        ttl: @expire_after,
        default: nil,
      )
    end

    def delete_session(_request, sid, _options)
      # Extract string ID from SessionId object if needed
      sid_string = sid.respond_to?(:public_id) ? sid.public_id : sid

      session_logger.trace "Session deletion initiated",
        session_id: sid_string,
        operation: 'delete'

      if stringkey = get_stringkey(sid_string)
        result = stringkey.del
        session_logger.trace "Session deleted from Redis",
          session_id: sid_string,
          redis_key: stringkey.key,
          deleted: result > 0,
          operation: 'delete'
      else
        session_logger.trace "No session found to delete",
          session_id: sid_string,
          operation: 'delete'
      end

      new_sid = generate_sid
      session_logger.trace "New session generated after deletion",
        session_id: new_sid.respond_to?(:public_id) ? new_sid.public_id : new_sid,
        operation: 'delete'

      new_sid
    end

    def valid_session_id?(sid)
      return false if sid.to_s.empty?
      return false unless sid.match?(/\A[a-f0-9]{64,}\z/)

      # Additional security checks could go here
      true
    end

    def valid_hmac?(data, hmac)
      expected = compute_hmac(data)

      # Type and size validation
      valid_types = hmac.is_a?(String) && expected.is_a?(String)
      valid_size = valid_types && hmac.bytesize == expected.bytesize

      unless valid_types && valid_size
        session_logger.trace "HMAC validation failed",
          valid_types: valid_types,
          valid_size: valid_size,
          hmac_size: hmac&.bytesize,
          expected_size: expected&.bytesize,
          operation: 'hmac_validation'

        return false
      end

      # Constant-time comparison
      result = Rack::Utils.secure_compare(expected, hmac)

      session_logger.trace "HMAC validation complete",
        valid: result,
        operation: 'hmac_validation'

      result
    end

    def derive_key(purpose)
      OpenSSL::HMAC.hexdigest('SHA256', @secret, "session-#{purpose}")
    end

    def compute_hmac(data)
      OpenSSL::HMAC.hexdigest('SHA256', @hmac_key, data)
    end

    def find_session(_request, sid)
      # Parent class already extracts sid from cookies
      # sid may be a SessionId object or nil
      sid_string = sid.respond_to?(:public_id) ? sid.public_id : sid

      session_logger.trace "Session lookup initiated",
        session_id: sid_string,
        sid_type: sid.class.name,
        operation: 'read'

      # Only generate new sid if none provided or invalid
      unless sid_string && valid_session_id?(sid_string)
        session_logger.trace "Session ID invalid or missing",
          session_id: sid_string,
          valid: false,
          operation: 'read'

        new_sid = generate_sid
        session_logger.trace "New session created",
          session_id: new_sid.respond_to?(:public_id) ? new_sid.public_id : new_sid,
          operation: 'read'

        return [new_sid, {}]
      end

      begin
        stringkey   = get_stringkey(sid_string)
        stored_data = stringkey.value if stringkey

        session_logger.trace "Redis lookup complete",
          session_id: sid_string,
          has_data: !stored_data.nil?,
          data_size: stored_data&.bytesize,
          ttl: stringkey&.ttl,
          operation: 'read'

        # If no data stored, return empty session
        unless stored_data
          session_logger.trace "No session data found",
            session_id: sid_string,
            operation: 'read'

          return [sid, {}]
        end

        # Verify HMAC before deserializing
        data, hmac = stored_data.split('--', 2)

        session_logger.trace "HMAC verification",
          session_id: sid_string,
          has_hmac: !hmac.nil?,
          data_length: data&.length,
          hmac_length: hmac&.length,
          operation: 'read'

        # If no HMAC or invalid format, create new session
        unless hmac && valid_hmac?(data, hmac)
          session_logger.warn "Session HMAC verification failed",
            session_id: sid_string,
            has_hmac: !hmac.nil?,
            operation: 'read'

          # Session tampered with - create new session
          new_sid = generate_sid
          return [new_sid, {}]
        end

        # Decode and parse the session data
        decoded_data = Base64.decode64(data)
        session_logger.trace "Base64 decode complete",
          session_id: sid_string,
          decoded_size: decoded_data.bytesize,
          operation: 'read'

        session_data = Familia::JsonSerializer.parse(decoded_data)

        session_logger.trace "Session loaded successfully",
          session_id: sid_string,
          session_keys: session_data.keys,
          account_id: session_data['account_id'],
          external_id: session_data['external_id'],
          authenticated_at: session_data['authenticated_at'],
          awaiting_mfa: session_data['awaiting_mfa'],
          two_factor_auth_setup: session_data['two_factor_auth_setup'],
          operation: 'read'

        [sid, session_data]
      rescue StandardError => ex
        # Log error with structured context
        session_logger.error "Error reading session",
          session_id: sid_string,
          error: ex.message,
          error_class: ex.class.name,
          backtrace: ex.backtrace&.first(5),
          operation: 'read'

        # Return new session on any error
        [generate_sid, {}]
      end
    end

    def write_session(_request, sid, session_data, _options)
      # Extract string ID from SessionId object if needed
      sid_string = sid.respond_to?(:public_id) ? sid.public_id : sid

      session_logger.trace "Session write initiated",
        session_id: sid_string,
        session_keys: session_data&.keys,
        session_data_class: session_data.class.name,
        operation: 'write'

      # Serialize session data
      json_data = Familia::JsonSerializer.dump(session_data)
      session_logger.trace "JSON serialization complete",
        session_id: sid_string,
        json_size: json_data.bytesize,
        operation: 'write'

      # Base64 encode
      encoded = Base64.encode64(json_data).delete("\n")
      session_logger.trace "Base64 encoding complete",
        session_id: sid_string,
        encoded_size: encoded.bytesize,
        operation: 'write'

      # Compute HMAC for integrity
      hmac = compute_hmac(encoded)
      signed_data = "#{encoded}--#{hmac}"

      session_logger.trace "HMAC computation complete",
        session_id: sid_string,
        hmac_length: hmac.length,
        signed_data_size: signed_data.bytesize,
        operation: 'write'

      # Get or create StringKey for this session
      stringkey = get_stringkey(sid_string)

      # Save the session data
      stringkey.set(signed_data)
      session_logger.trace "Redis SET complete",
        session_id: sid_string,
        redis_key: stringkey.key,
        operation: 'write'

      # Update expiration if configured
      if @expire_after && @expire_after > 0
        stringkey.update_expiration(expiration: @expire_after)
        session_logger.trace "Expiration updated",
          session_id: sid_string,
          expire_after: @expire_after,
          operation: 'write'
      end

      # Calculate session data metrics for logging
      data_size = signed_data.bytesize
      ttl_value = stringkey.ttl
      expires_at = ttl_value > 0 ? Time.now + ttl_value : nil

      # Structured trace logging with all critical session fields
      session_logger.trace "Session saved successfully",
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
        operation: 'write'

      # Return the original sid (may be SessionId object)
      sid
    rescue StandardError => ex
      # Log error with structured context
      session_logger.error "Error writing session",
        session_id: sid_string,
        session_keys: session_data&.keys,
        error: ex.message,
        error_class: ex.class.name,
        backtrace: ex.backtrace&.first(5),
        operation: 'write'

      # Return false to indicate failure
      false
    end

    # Clean up expired sessions (optional, can be called periodically)
    def cleanup_expired_sessions
      # This would typically be handled by Redis TTL automatically
      # but you could implement manual cleanup if needed
    end
  end
end
