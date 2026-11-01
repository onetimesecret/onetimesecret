# lib/onetime/models/custom_domain/sso_signin_outcome.rb
#
# frozen_string_literal: true

#
# CustomDomain::SsoSigninOutcome - The last tenant SSO sign-in outcome per domain
#
# One small record per custom domain, written by the tenant SSO hooks and
# read by the domain SSO settings API, answering the one question the
# saved-configuration check cannot: did a real sign-in through this domain's
# IdP complete, and if the last one did not, where did it stop?
#
# WHAT IS STORED. Outcomes only, never identities: a result, a timestamp,
# the stage a failure stopped at and a bounded code. No email, uid, name,
# IP, session id or IdP error text. The code is one of the stable
# `auth_error` values the sign-in page already shows the visitor
# (`invalid_email`, `domain_not_allowed`, `sso_config_unusable`, ...) or,
# at the provider stage, OmniAuth's error TYPE. For the OAuth2 family that
# type is the IdP's `error` parameter, which an unauthenticated client can
# shape on the callback URL, so every code passes through
# {.sanitize_code} (lowercase, `[a-z0-9_.-]`, 64 bytes) before it is stored
# or served.
#
# SEPARATE FROM SsoConfig, deliberately. SsoConfig is owner-written and
# audited (ChangeLogger), and its `updated` stamp is the configuration
# revision the settings UI reasons about; an unauthenticated sign-in must
# never touch that record. This one is runtime state with its own TTL
# (OUTCOME_TTL): it expires on its own if the domain goes quiet, is cleaned
# up with the SsoConfig (DeleteSsoConfig), and is never part of a backup
# anyone restores a configuration from. Reads require the same configuration
# incarnation, so failed cleanup cannot expose old history on a replacement.
# Unbound outcomes written before incarnation tracking are ignored.
#
# BEST-EFFORT, NEVER A GATE. Every writer rescues and logs: a Redis error
# while recording an outcome must not fail or alter the sign-in it
# describes. Readers get nil when there is nothing (or nothing readable).
#
# STAGES, in flow order (which hook writes them is in the hooks):
#   setup     refused before the IdP was contacted (sso_config_unusable)
#   provider  the IdP or the OmniAuth strategy failed the callback
#             (omniauth_on_failure: invalid_credentials, access_denied,
#             csrf_detected, timeout, ...)
#   callback  the callback came back but the tenant gates refused it
#             (tenant_mismatch, tenant_context_missing, the email-domain
#             allowlist: domain_not_allowed, missing_email, invalid_email)
#   account   the identity was accepted but no account could sign in
#             (JIT create refusals, tenant_sso_link_unavailable,
#             org_join_failed)
#
# Redis key: custom_domain__sso_signin_outcome:{domain_id}:object (Horreum)
#
class Onetime::CustomDomain::SsoSigninOutcome < Familia::Horreum
  using Familia::Refinements::TimeLiterals

  feature :expiration

  # Renewed on every write. A domain nobody signs in through for this long
  # has no "last sign-in" worth showing, and the record's absence reads as
  # "none recorded", which is accurate.
  OUTCOME_TTL = 90.days
  default_expiration OUTCOME_TTL

  prefix :custom_domain__sso_signin_outcome

  RESULTS = %w[succeeded failed].freeze
  STAGES  = %w[setup provider callback account].freeze

  # The stored form of a code: what sanitize_code produces.
  CODE_FORMAT  = /\A[a-z0-9_.-]{1,64}\z/
  CODE_MAX     = 64
  UNKNOWN_CODE = 'unknown'

  identifier_field :domain_id
  field :domain_id
  field :config_generation
  field :last_order
  field :last_succeeded_order
  field :last_failed_order

  field :last_result          # one of RESULTS
  field :last_at              # Unix epoch seconds of the last outcome
  field :last_provider_type   # SsoConfig#provider_type at the time, when known
  field :last_succeeded_at    # Unix epoch seconds of the last success, if any
  field :last_failed_at       # Unix epoch seconds of the last failure, if any
  field :last_failure_stage   # one of STAGES, for the last failure
  field :last_failure_code    # sanitized code, for the last failure

  # Like StateCas, operands use Familia's scalar serialization. All checks,
  # partial updates and TTL renewal execute in one Redis operation. Event time
  # orders each result independently; equal times use Redis execution order.
  WRITE_SCRIPT = <<~LUA
    local generation = redis.call('HGET', KEYS[2], 'outcome_generation')
    if not generation or generation == 'null' then
      local created = redis.call('HGET', KEYS[2], 'created')
      if not created or created == 'null' then return 0 end
      generation = cjson.encode('legacy:' .. tostring(cjson.decode(created)))
    end
    if generation ~= ARGV[1] then return 0 end

    if redis.call('HGET', KEYS[1], 'config_generation') ~= ARGV[1] then
      redis.call('DEL', KEYS[1])
    end
    redis.call('HSET', KEYS[1], 'config_generation', ARGV[1], 'domain_id', ARGV[2])
    local order = tonumber(ARGV[3])
    local previous = tonumber(redis.call('HGET', KEYS[1], 'last_order'))
    if not previous or order >= previous then
      redis.call('HSET', KEYS[1], 'last_order', ARGV[3], 'last_at', ARGV[4], 'last_result', ARGV[5])
      if ARGV[6] ~= '' then redis.call('HSET', KEYS[1], 'last_provider_type', ARGV[6]) end
    end
    local result = ARGV[7]
    local result_order = 'last_' .. result .. '_order'
    local previous_result = tonumber(redis.call('HGET', KEYS[1], result_order))
    if not previous_result or order >= previous_result then
      redis.call('HSET', KEYS[1], result_order, ARGV[3], 'last_' .. result .. '_at', ARGV[4])
      if result == 'failed' then
        redis.call('HSET', KEYS[1], 'last_failure_stage', ARGV[8], 'last_failure_code', ARGV[9])
      end
    end
    redis.call('EXPIRE', KEYS[1], ARGV[10])
    return 1
  LUA

  DELETE_SCRIPT = <<~LUA
    if redis.call('HGET', KEYS[1], 'config_generation') == ARGV[1] then
      return redis.call('DEL', KEYS[1])
    end
    return 0
  LUA

  class << self
    # @param domain_id [String] CustomDomain identifier
    # @return [SsoSigninOutcome, nil]
    def find_by_domain_id(domain_id, config: nil)
      return nil if domain_id.to_s.empty?

      config ||= Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain_id)
      return nil unless config&.domain_id == domain_id && config.signin_outcome_generation

      outcome = load(domain_id)
      outcome if outcome&.config_generation == config.signin_outcome_generation
    end

    # Record a completed tenant SSO sign-in. Best-effort (see class comment).
    #
    # @param domain_id [String] the VALIDATED CustomDomain identifier
    # @param config [SsoConfig, nil] captured config used by this flow; nil skips
    # @param provider_type [String, nil] SsoConfig#provider_type when known
    # @param now [Time]
    # @return [SsoSigninOutcome, nil] nil when nothing was recorded
    def record_success!(domain_id, config: nil, provider_type: nil, now: Time.now)
      return nil if domain_id.to_s.empty?

      write(domain_id, config, provider_type, now, 'succeeded')
    rescue StandardError => ex
      log_write_failure('record_success!', domain_id, ex)
      nil
    end

    # Record a tenant SSO sign-in that did not complete. Best-effort.
    #
    # @param domain_id [String] the CustomDomain identifier the flow belongs
    #   to (validated where the stage has one; the flow's starting domain at
    #   the provider stage)
    # @param config [SsoConfig, nil] captured config used by this flow; nil skips
    # @param stage [String, Symbol] one of STAGES
    # @param code [String, Symbol, nil] sanitized before storage
    # @param provider_type [String, nil]
    # @param now [Time]
    # @return [SsoSigninOutcome, nil] nil when nothing was recorded
    def record_failure!(domain_id, stage:, code:, config: nil, provider_type: nil, now: Time.now)
      return nil if domain_id.to_s.empty?

      stage = stage.to_s
      raise ArgumentError, "unknown stage #{stage.inspect}" unless STAGES.include?(stage)

      write(domain_id, config, provider_type, now, 'failed', stage, sanitize_code(code))
    rescue StandardError => ex
      log_write_failure('record_failure!', domain_id, ex)
      nil
    end

    # Pass the captured config when cleanup runs after deleting it. The guard
    # also prevents delayed cleanup from erasing a replacement's history.
    # @return [Boolean] whether a matching record existed and was removed
    def delete_for_domain!(domain_id, config: nil)
      config ||= Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain_id)
      return false unless config&.domain_id == domain_id && config.signin_outcome_generation

      outcome = new(domain_id: domain_id)
      outcome.dbclient.eval(
        DELETE_SCRIPT,
        keys: [outcome.dbkey],
        argv: [outcome.serialize_value(config.signin_outcome_generation)],
      ).to_i == 1
    end

    # Lowercase; anything outside [a-z0-9_.-] becomes '_'; at most CODE_MAX
    # bytes; a blank input becomes UNKNOWN_CODE. Idempotent on its own
    # output.
    #
    # @param code [Object]
    # @return [String] matches CODE_FORMAT
    def sanitize_code(code)
      text = code.to_s.dup.force_encoding('UTF-8').scrub('_').downcase
      text = text.gsub(/[^a-z0-9_.-]/, '_')[0, CODE_MAX].to_s
      text.empty? ? UNKNOWN_CODE : text
    end

    private

    # Never re-fetch a writer's config: it must be the snapshot actually used
    # by the flow. A missing/deleted/replaced config cannot create an outcome.
    def write(domain_id, config, provider_type, now, result, stage = nil, code = nil)
      return nil unless config&.domain_id == domain_id && config.signin_outcome_generation

      outcome = new(domain_id: domain_id.to_s)
      encode  = outcome.method(:serialize_value)
      argv    = [
        encode.call(config.signin_outcome_generation), encode.call(domain_id.to_s),
        encode.call(now.to_f), encode.call(now.to_i), encode.call(result),
        provider_type.to_s.empty? ? '' : encode.call(provider_type.to_s), result,
        encode.call(stage), encode.call(code), OUTCOME_TTL.to_i
      ]
      written = outcome.dbclient.eval(WRITE_SCRIPT, keys: [outcome.dbkey, config.dbkey], argv: argv)
      find_by_domain_id(domain_id, config: config) if written.to_i == 1
    end

    def log_write_failure(method, domain_id, ex)
      OT.le "[SsoSigninOutcome] #{method} failed for domain #{domain_id.to_s[0, 12]}: #{ex.class.name}"
    end
  end

  def succeeded?
    last_result == 'succeeded'
  end

  def failed?
    last_result == 'failed'
  end

  # The API shape (domain SSO settings `record.last_sign_in`). Timestamps are
  # Unix epoch seconds (Integer) or nil, like created_at / updated_at on the
  # SSO record. Never carries anything but what this record stores.
  #
  # @return [Hash]
  def to_api_h
    {
      result: last_result.to_s,
      at: epoch_or_nil(last_at),
      succeeded_at: epoch_or_nil(last_succeeded_at),
      failed_at: epoch_or_nil(last_failed_at),
      failure_stage: blank_to_nil(last_failure_stage),
      failure_code: blank_to_nil(last_failure_code),
      provider_type: blank_to_nil(last_provider_type),
    }
  end

  private

  def epoch_or_nil(value)
    text = value.to_s
    text.match?(/\A\d+\z/) ? text.to_i : nil
  end

  def blank_to_nil(value)
    text = value.to_s
    text.empty? ? nil : text
  end
end
