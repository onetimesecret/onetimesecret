# lib/onetime/models/custom_domain/homepage_config.rb
#
# frozen_string_literal: true

require_relative '../features/boolean_encoding'
require_relative '../../utils/cidr_list'

#
# CustomDomain::HomepageConfig - Per-domain homepage secrets configuration
#
# This model stores homepage configuration bound to a specific CustomDomain.
# When enabled, anonymous users can create secrets on the domain's public
# homepage without authentication.
#
# Network rules (allowed_cidrs / denied_cidrs) narrow WHO gets the
# interactive homepage once it is enabled: a visitor in a denied range, or
# outside every allowed range when any are configured, gets the private
# landing page and is refused anonymous secret creation on the domain —
# the same fail-closed rendering and 403 as a disabled homepage, so the
# rule's existence is not advertised. Both lists empty (the default, and
# every record that pre-dates the fields) means no network restriction.
# Membership is judged through the request's env['otto.ip_match'] closure
# at full /32–/128 precision (see #network_allowed?).
#
# This is the single source of truth for homepage settings. The legacy
# allow_public_homepage field on BrandSettings was retired in #3026 once
# the #3023 backfill migration guaranteed every CustomDomain has a record.
# CustomDomain.create! bootstraps a default-disabled record so the
# invariant holds for new domains as well.
#
# @see IncomingConfig - Similar pattern for incoming secrets recipients
#
class Onetime::CustomDomain::HomepageConfig < Familia::Horreum
  include Familia::Features::Autoloader

  SCHEMA = 'models/domain-homepage-config'

  # Recognised disabled-homepage variants (mirrors the frontend
  # disabledHomepageVariantSchema). Anything else is treated as nil so the
  # domain falls back to the deployment-wide / frontend default.
  VALID_DISABLED_HOMEPAGE_VARIANTS = %w[v1 minimal closed].freeze

  # Recognised homepage secrets modes. When the homepage is enabled,
  # this selects WHICH interactive experience anonymous visitors get:
  #   'create'   - the classic secret-creation form (historical behavior)
  #   'incoming' - the incoming-secrets form (send a secret TO the
  #                domain's configured IncomingConfig recipients)
  # Unset/blank values read as 'create' via secrets_mode_value so records
  # that pre-date this field keep their existing behavior. An unrecognised
  # non-blank value coerces to 'create' for display too, but the security
  # gates (effectively_enabled?, CustomDomain#allow_public_secret_creation?)
  # deliberately DO NOT trust that coercion — they fail closed on it via
  # recognized_secrets_mode? rather than exposing a form the operator never
  # chose. Not to be confused with the site-level homepage "mode"
  # (internal/external CIDR detection in Helpers::HomepageModeHelpers) —
  # that gates WHO sees the interactive homepage; this selects WHAT the
  # interactive homepage is.
  VALID_SECRETS_MODES  = %w[create incoming].freeze
  DEFAULT_SECRETS_MODE = 'create'

  # Cap on distinct ranges per network-rule list (allowed_cidrs and
  # denied_cidrs each). Shared with the normalizer so the write-time check
  # and the error message cannot disagree.
  MAX_CIDRS = Onetime::Utils::CidrList::MAX_ENTRIES

  # Refusal from {#allowed_cidrs=} / {#denied_cidrs=} for an entry that is
  # not an IPv4/IPv6 address or CIDR range. Typed the way
  # SignupConfig::InvalidAllowedSignupDomain is: it carries the refused
  # entry, its field and a locale key so an API layer can show it against
  # the field in the operator's language.
  class InvalidCidr < Onetime::Problem
    ERROR_KEY = 'api.domains.errors.homepage_cidr_invalid'

    attr_reader :field, :cidr

    def initialize(field, cidr, reason = nil)
      @field = field.to_s
      @cidr  = cidr.to_s
      super(reason ? "Invalid CIDR: #{@cidr} (#{reason})" : "Invalid CIDR: #{@cidr}")
    end

    def error_key = ERROR_KEY
    def args      = { cidr: cidr }
  end

  # Refusal from {#allowed_cidrs=} / {#denied_cidrs=} for a list with more
  # than MAX_CIDRS distinct ranges.
  class TooManyCidrs < Onetime::Problem
    ERROR_KEY = 'api.domains.errors.homepage_cidrs_max_exceeded'

    attr_reader :field, :max

    def initialize(field, count, max = MAX_CIDRS)
      @field = field.to_s
      @max   = max
      super("#{@field} accepts at most #{max} entries (got #{count})")
    end

    def error_key = ERROR_KEY
    def args      = { max: max }
  end

  prefix :custom_domain__homepage_config

  # domain_id is the CustomDomain's identifier (objid), used as our key.
  # This creates a 1:1 relationship: one homepage config per domain.
  identifier_field :domain_id
  field :domain_id

  # Whether homepage secrets is enabled for this domain
  field :enabled

  # DEPRECATED, read-echo-only (#3672, ADR-030): these fields carry no
  # display authority. Per-domain homepage auth links are governed by the
  # SigninConfig/SignupConfig records — the bootstrap serializer computes
  # the masthead values from those resolvers, never from these fields.
  # The 2026-07-03 migration (disable_homepage_auth_links) flipped all
  # stored values to false, and PUT /homepage-config ignores the params
  # with a deprecation warning. Kept only because GET/PUT responses still
  # echo the stored values (round-trip tolerance for read-modify-write
  # clients) until the fields are removed in a later release.
  field :signup_enabled
  field :signin_enabled

  # Which disabled-homepage variant this domain renders when the homepage
  # secret form is gated by auth. nil (unset) = fall back to the
  # deployment-wide custom-domain default
  # (site.interface.ui.homepage.custom_disabled_variant) and ultimately the
  # frontend DEFAULT_DISABLED_HOMEPAGE_VARIANT constant. Custom domains do
  # NOT inherit the canonical-site disabled_variant — the two tiers are
  # kept decoupled.
  field :disabled_homepage_variant

  # Which interactive experience the homepage offers when enabled
  # ('create' | 'incoming'). nil/unset (legacy records) reads as 'create'
  # via secrets_mode_value, preserving pre-existing behavior.
  field :secrets_mode

  # Network rules, each a JSON array of canonical "address/prefix" strings
  # (see Onetime::Utils::CidrList) or nil when the list is empty. Read
  # through #allowed_cidrs / #denied_cidrs; write ONLY through the
  # validating setters (#allowed_cidrs= / #denied_cidrs=), which is also
  # what the registry's apply_field and this model's upsert/create! do.
  # nil on every record that pre-dates the fields = no restriction.
  field :allowed_cidrs_json
  field :denied_cidrs_json

  # Timestamps (Unix epoch integers)
  field :created
  field :updated

  # Colonel-writable fields, aggregated into
  # {Onetime::CustomDomain::ConfigRegistry::FIELD_SPECS} (the registry
  # validates at load time that every key has a setter here). `enabled`
  # stores a legacy 'true'/'false' STRING; the boolean_encoding feature
  # (below) normalizes writes to that encoding and keeps #enabled?
  # tolerant of both (#3951). The deprecated signup_enabled/signin_enabled
  # read-echo fields are deliberately NOT writable (ADR-030: no display
  # authority) and NOT covered by the feature — they keep their strict
  # `== true` predicates.
  #
  # Colonel PUT deliberately BYPASSES the workspace write gate on
  # secrets_mode (incoming_secrets entitlement + a ready IncomingConfig)
  # as admin-repair power; read paths still fail closed via
  # #effectively_enabled?.
  #
  # allowed_cidrs / denied_cidrs route through the model setters, which
  # normalize and validate each entry (raising InvalidCidr / TooManyCidrs,
  # both Onetime::Problem) — same contract as SignupConfig's
  # allowed_signup_domains string_array.
  FIELD_SPECS = {
    'enabled' => { type: :boolean, storage: :string },
    'secrets_mode' => { type: :enum, values: VALID_SECRETS_MODES, nullable: false },
    'disabled_homepage_variant' => { type: :enum, values: VALID_DISABLED_HOMEPAGE_VARIANTS, nullable: true },
    'allowed_cidrs' => { type: :string_array },
    'denied_cidrs' => { type: :string_array },
  }.freeze

  # Tolerant predicates + normalizing setters for the boolean fields in
  # FIELD_SPECS above (#3951). Must come after both the field
  # declarations and the constant. Provides #enabled? / #enabled=;
  # deliberately does NOT cover the deprecated signup_enabled /
  # signin_enabled read-echo fields (not in the specs).
  feature :boolean_encoding

  def init
    self.enabled      ||= 'false'
    self.signup_enabled = false if signup_enabled.nil?
    self.signin_enabled = false if signin_enabled.nil?
    # init runs for new objects only (Familia loads via allocate), so this
    # makes freshly created records self-describing without masking legacy
    # records' nil field — those still read as 'create' via secrets_mode_value.
    self.secrets_mode ||= DEFAULT_SECRETS_MODE
  end

  # Whether the Sign Up link should render on this domain's homepage.
  # Conservative default: only an explicit boolean `true` shows the link.
  # A missing/nil field (legacy records pre-dating this field) reads as
  # false, so the link stays hidden until an operator opts in. A stray
  # string value ('true'/'false') is likewise treated as disabled.
  def signup_enabled?
    signup_enabled == true
  end

  # Whether the Sign In link should render on this domain's homepage.
  # Conservative default: only an explicit boolean `true` shows the link.
  def signin_enabled?
    signin_enabled == true
  end

  # Recognised disabled-homepage variant for this domain, or nil to fall
  # back to the deployment-wide / frontend default. Guards against blank or
  # stale values in Redis (records pre-dating this field have none).
  def disabled_homepage_variant_value
    self.class.coerce_disabled_homepage_variant(disabled_homepage_variant)
  end

  # Effective homepage secrets mode ('create' | 'incoming'). Records that
  # pre-date the field (nil) and stray/unknown values both read as
  # 'create' so legacy domains keep their historical behavior.
  def secrets_mode_value
    self.class.coerce_secrets_mode(secrets_mode)
  end

  # Whether this domain's homepage presents the incoming-secrets form
  # (rather than the classic secret-creation form) when enabled.
  def incoming_mode?
    secrets_mode_value == 'incoming'
  end

  # Whether the stored secrets_mode is one we can interpret: blank (a
  # legacy/unset record, which reads as the historical 'create') or a value
  # in VALID_SECRETS_MODES. A non-blank value we don't recognise is treated
  # as corruption. The security gates (effectively_enabled? and
  # CustomDomain#allow_public_secret_creation?) fail closed on it rather
  # than letting secrets_mode_value's display coercion silently turn it into
  # the public create form. Not reachable through the model's own writers
  # (upsert / create! coerce) or the PUT API (rejects unknown modes); this
  # guards against direct Redis writes and botched migrations.
  def recognized_secrets_mode?
    v = secrets_mode.to_s.strip
    v.empty? || VALID_SECRETS_MODES.include?(v)
  end

  # Ranges that may use the interactive homepage. Empty = everyone not
  # denied. Unreadable stored JSON reads as [] here (display), and as a
  # fail-closed deny in #network_allowed? via #allowed_cidrs_corrupt?.
  #
  # @return [Array<String>] canonical "address/prefix" entries
  def allowed_cidrs
    read_cidr_list(allowed_cidrs_json)
  end

  # Replace the allowed ranges. Entries are normalized (canonical form,
  # de-duplicated, host bits below the prefix dropped) and validated.
  #
  # @param entries [Array<String>, nil] nil or [] clears the list
  # @raise [InvalidCidr, TooManyCidrs]
  def allowed_cidrs=(entries)
    self.allowed_cidrs_json = encode_cidr_list('allowed_cidrs', entries)
  end

  # Ranges that may never use the interactive homepage; checked before
  # the allow list, so a deny match wins. Empty = no denials.
  #
  # @return [Array<String>]
  def denied_cidrs
    read_cidr_list(denied_cidrs_json)
  end

  # Replace the denied ranges. Same normalization and validation as
  # {#allowed_cidrs=}.
  #
  # @param entries [Array<String>, nil] nil or [] clears the list
  # @raise [InvalidCidr, TooManyCidrs]
  def denied_cidrs=(entries)
    self.denied_cidrs_json = encode_cidr_list('denied_cidrs', entries)
  end

  # Whether allowed_cidrs_json holds something we cannot read as a list.
  # Absent/empty is NOT corrupt (the cleared state the setter writes).
  # Mirrors SignupConfig#allowed_signup_domains_corrupt?.
  def allowed_cidrs_corrupt?
    cidr_list_corrupt?(allowed_cidrs_json)
  end

  # Whether denied_cidrs_json holds something we cannot read as a list.
  def denied_cidrs_corrupt?
    cidr_list_corrupt?(denied_cidrs_json)
  end

  # Whether this domain narrows the interactive homepage by network at all
  # (either list non-empty, or a stored list unreadable — which
  # #network_allowed? treats as a restriction that denies everyone).
  def network_restricted?
    allowed_cidrs_corrupt? || denied_cidrs_corrupt? ||
      !(allowed_cidrs.empty? && denied_cidrs.empty?)
  end

  # Whether the requesting client's network may use the interactive
  # homepage. Consumed by the bootstrap serializer (together with
  # #effectively_enabled?) and by CustomDomain#allow_public_secret_creation?
  # (the anonymous create-API gate), so the form a visitor sees and the API
  # it posts to can never disagree.
  #
  # Decision (Onetime::Utils::CidrList.permitted?): no rules → true; a
  # denied range matches → false; allowed ranges configured and none
  # matches → false; otherwise true. Deny wins.
  #
  # Membership is judged ONLY through the env['otto.ip_match'] verdict
  # closure IPPrivacyMiddleware installs over the resolved PRE-MASK client
  # IP (handed in by the request layer as `ip_match`): env['otto.client_ip']
  # and req.ip are privacy-masked (/24, /48) and would misjudge any finer
  # range in both directions, and the unmasked address never reaches this
  # code. Same pattern as AdminNetworkIsolation#network_allowed? and
  # HomepageModeHelpers#homepage_cidrs_match?.
  #
  # Fail closed whenever rules exist but cannot be judged: no callable
  # matcher in the request (a stack that never ran IPPrivacyMiddleware), no
  # resolvable client IP, an unreadable stored list, a stored entry that no
  # longer parses, or any error from the matcher. A domain with no rules is
  # never affected by any of these.
  #
  # @param ip_match [#call, nil] env['otto.ip_match'] for the request
  # @return [Boolean]
  def network_allowed?(ip_match)
    if allowed_cidrs_corrupt? || denied_cidrs_corrupt?
      OT.le "[HomepageConfig] network rules unreadable for domain #{domain_id}; denying"
      return false
    end

    allowed = allowed_cidrs
    denied  = denied_cidrs
    return true if allowed.empty? && denied.empty?

    unless ip_match.respond_to?(:call)
      OT.le "[HomepageConfig] network rules configured for domain #{domain_id} but the request " \
            'carries no otto.ip_match closure; denying'
      return false
    end

    permitted = Onetime::Utils::CidrList.permitted?(ip_match, allowed: allowed, denied: denied)
    OT.ld "[HomepageConfig] network rules denied a visitor on domain #{domain_id}" unless permitted
    permitted
  rescue StandardError => ex
    # Error class only: an address-parse message can contain the address.
    OT.le "[HomepageConfig] network match failed for domain #{domain_id} (#{ex.class}); denying"
    false
  end

  # Whether the homepage is EFFECTIVELY interactive for anonymous
  # visitors right now. For create mode this is just enabled?; for
  # incoming mode it additionally requires that incoming can actually
  # receive secrets (see incoming_available?). This is the single
  # source of truth consumed by both the bootstrap serializer (read
  # path) and the homepage-config API responses, so the two can never
  # drift: a homepage pointed at an unavailable incoming form fails
  # closed to the non-interactive trust card.
  #
  # @param custom_domain [CustomDomain, nil] pass the already-loaded
  #   domain to avoid a redundant Redis read; falls back to loading it.
  # @return [Boolean]
  def effectively_enabled?(custom_domain: nil)
    return false unless enabled?
    # An unrecognised stored mode (corruption, a botched migration, or a
    # mode written by a newer app version) must not fall open to the public
    # create form the operator never selected — fail closed to the trust
    # card. Recognised legacy/blank still reads as the create form below.
    return false unless recognized_secrets_mode?
    return true unless incoming_mode?

    incoming_available?(custom_domain: custom_domain)
  end

  # Whether the domain can actually serve the incoming form to
  # anonymous visitors: site.secret present (recipient hashes cannot be
  # computed without it — RecipientResolver fails closed the same way),
  # IncomingConfig ready (enabled with at least one recipient), and the
  # owning org still entitled. The install-wide features.incoming.enabled
  # flag is deliberately NOT consulted here: it gates the canonical domain
  # only, while custom domains self-govern via their own IncomingConfig
  # plus the incoming_secrets entitlement — the same canonical/custom split
  # RecipientResolver#enabled? enforces. Mirrors the PutHomepageConfig
  # secrets_mode=incoming write gate. Checks run cheapest-first (in-memory
  # config, one Redis read, org load).
  #
  # @param custom_domain [CustomDomain, nil] optional pre-loaded domain
  # @return [Boolean]
  def incoming_available?(custom_domain: nil)
    return false if OT.conf.dig('site', 'secret').to_s.strip.empty?

    incoming = Onetime::CustomDomain::IncomingConfig.find_by_domain_id(domain_id)
    return false unless incoming&.ready?

    domain = custom_domain || self.custom_domain
    domain&.primary_organization&.can?('incoming_secrets') || false
  end

  # Enable homepage secrets for this domain.
  # @return [void]
  def enable!
    self.enabled = 'true'
    self.updated = Familia.now.to_i
    save
  end

  # Disable homepage secrets for this domain.
  # @return [void]
  def disable!
    self.enabled = 'false'
    self.updated = Familia.now.to_i
    save
  end

  # Load the associated CustomDomain record.
  #
  # @return [CustomDomain, nil] The domain or nil if not found
  def custom_domain
    Onetime::CustomDomain.find_by_identifier(domain_id)
  end

  # Load the owning Organization via the CustomDomain.
  #
  # @return [Organization, nil] The organization or nil if not found
  def organization
    domain = custom_domain
    return nil unless domain

    Onetime::Organization.load(domain.org_id)
  end

  # Validate configuration.
  #
  # @return [Array<String>] List of validation error messages
  def validation_errors
    errors = []
    errors << 'domain_id is required' if domain_id.to_s.empty?
    unless disabled_homepage_variant.to_s.empty? ||
           VALID_DISABLED_HOMEPAGE_VARIANTS.include?(disabled_homepage_variant.to_s)
      errors << "invalid disabled_homepage_variant: #{disabled_homepage_variant}"
    end
    unless secrets_mode.to_s.empty? || VALID_SECRETS_MODES.include?(secrets_mode.to_s)
      errors << "invalid secrets_mode: #{secrets_mode}"
    end
    errors << 'allowed_cidrs is unreadable' if allowed_cidrs_corrupt?
    errors << 'denied_cidrs is unreadable' if denied_cidrs_corrupt?
    errors
  end

  # Check if the configuration is valid.
  #
  # @return [Boolean] true if no validation errors
  def valid?
    validation_errors.empty?
  end

  private

  # Stored JSON list → Array<String>. Unreadable → [] (see *_corrupt?).
  def read_cidr_list(raw)
    return [] if raw.to_s.empty?

    parsed = JSON.parse(raw)
    parsed.is_a?(Array) ? parsed.map(&:to_s) : []
  rescue JSON::ParserError
    []
  end

  # Array<String> → stored JSON (nil when empty), normalizing and
  # validating through CidrList and re-typing its refusals against the
  # field so API layers can report them in place.
  def encode_cidr_list(field, entries)
    normalized = Onetime::Utils::CidrList.normalize(entries)
    normalized.empty? ? nil : JSON.generate(normalized)
  rescue Onetime::Utils::CidrList::InvalidEntry => ex
    raise InvalidCidr.new(field, ex.entry, ex.message)
  rescue Onetime::Utils::CidrList::TooManyEntries => ex
    raise TooManyCidrs.new(field, ex.count, ex.max)
  end

  # Present but not a JSON array → corrupt. Absent/empty is the cleared
  # state the setters write, never corrupt.
  def cidr_list_corrupt?(raw)
    str = raw.to_s
    return false if str.empty?

    !JSON.parse(str).is_a?(Array)
  rescue JSON::ParserError
    true
  end

  public

  class << self
    # Normalise a disabled-homepage variant to a recognised id, or nil
    # (= use the deployment-wide / frontend default). Blank and unknown
    # values both collapse to nil.
    def coerce_disabled_homepage_variant(value)
      v = value.to_s.strip
      VALID_DISABLED_HOMEPAGE_VARIANTS.include?(v) ? v : nil
    end

    # Normalise a homepage secrets mode to a recognised id for DISPLAY and
    # merge-write purposes. Blank and unknown values collapse to
    # DEFAULT_SECRETS_MODE ('create') so legacy records and stray Redis
    # values keep historical behavior. Security decisions do NOT rely on
    # this coercion: the read-time gates use recognized_secrets_mode? to
    # fail closed on an unknown value instead of treating it as create.
    def coerce_secrets_mode(value)
      v = value.to_s.strip
      VALID_SECRETS_MODES.include?(v) ? v : DEFAULT_SECRETS_MODE
    end

    # Find homepage config by domain ID.
    #
    # @param domain_id [String] CustomDomain identifier (objid)
    # @return [CustomDomain::HomepageConfig, nil] The config or nil if not found
    def find_by_domain_id(domain_id)
      return nil if domain_id.to_s.empty?

      load(domain_id)
    end

    # Check if a domain has homepage config.
    #
    # @param domain_id [String] CustomDomain identifier
    # @return [Boolean] true if homepage config exists
    def exists_for_domain?(domain_id)
      return false if domain_id.to_s.empty?

      exists?(domain_id)
    end

    # Create or update homepage config for a domain.
    #
    # Prefer this over create! for PUT endpoints: reduces the chance of a
    # duplicate-create error under concurrent requests. Last write wins for
    # the same domain_id key; created timestamp may reflect the second writer
    # on a first-write race. Not fully atomic — use a Lua script if strict
    # once-only create semantics are needed.
    #
    # @param domain_id [String] CustomDomain identifier
    # @param enabled [Boolean, String] Whether to enable homepage secrets.
    #   Required by every call site; any non-truthy value (including nil)
    #   is normalized to the stored 'false' by the boolean_encoding
    #   setter — the safe default, but not a validated one, so don't rely
    #   on this to reject bad input.
    # @param signup_enabled [Boolean, nil] DEPRECATED (#3672, ADR-030):
    #   the field carries no display authority (see the field declaration).
    #   The API no longer passes it; kept so the disable_homepage_auth_links
    #   migration and its tryout can stage/clear stored state. Merge
    #   semantics: nil leaves the stored value unchanged.
    # @param signin_enabled [Boolean, nil] DEPRECATED — same as
    #   signup_enabled above.
    # @param disabled_homepage_variant [String, nil] Merge semantics:
    #   nil leaves the stored value unchanged;
    #   "" (or any unrecognised value) clears the override back to the default;
    #   a recognised id ('v1' | 'minimal' | 'closed') sets it.
    # @param secrets_mode [String, nil] Merge semantics: nil leaves the stored
    #   value unchanged; "" (or any unrecognised value) resets to 'create';
    #   a recognised id ('create' | 'incoming') sets it.
    # @param allowed_cidrs [Array<String>, nil] Merge semantics: nil leaves
    #   the stored list unchanged; [] clears it; otherwise replaces it with
    #   the normalized entries (see #allowed_cidrs=). Validation errors
    #   (InvalidCidr / TooManyCidrs) raise BEFORE anything is written.
    # @param denied_cidrs [Array<String>, nil] Same semantics as allowed_cidrs.
    # @return [CustomDomain::HomepageConfig] The config (created or updated)
    # @raise [InvalidCidr, TooManyCidrs] when a CIDR list is refused
    def upsert(domain_id:, enabled:, signup_enabled: nil, signin_enabled: nil, disabled_homepage_variant: nil,
               secrets_mode: nil, allowed_cidrs: nil, denied_cidrs: nil)
      raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?

      config = find_by_domain_id(domain_id)
      now    = Familia.now.to_i

      if config
        config.created                 ||= now  # repair missing created from legacy records
        config.enabled                   = enabled
        config.signup_enabled            = signup_enabled unless signup_enabled.nil?
        config.signin_enabled            = signin_enabled unless signin_enabled.nil?
        config.disabled_homepage_variant = coerce_disabled_homepage_variant(disabled_homepage_variant) unless disabled_homepage_variant.nil?
        config.secrets_mode              = coerce_secrets_mode(secrets_mode) unless secrets_mode.nil?
        config.updated                   = now
      else
        config = new(
          domain_id: domain_id,
          enabled: enabled.to_s,
          signup_enabled: signup_enabled.nil? ? false : signup_enabled,
          signin_enabled: signin_enabled.nil? ? false : signin_enabled,
          disabled_homepage_variant: coerce_disabled_homepage_variant(disabled_homepage_variant),
          secrets_mode: coerce_secrets_mode(secrets_mode),
          created: now,
          updated: now,
        )
      end

      # Validating setters: a refused entry raises here, before save, so a
      # bad list never partially lands alongside the other fields.
      config.allowed_cidrs = allowed_cidrs unless allowed_cidrs.nil?
      config.denied_cidrs  = denied_cidrs unless denied_cidrs.nil?

      config.save
      config
    end

    # Atomically return an existing HomepageConfig or create one if absent.
    #
    # Backfill/bootstrap counterpart to upsert. A concurrent writer that
    # created a record between the caller's read and our write gets their
    # value preserved — this method never overwrites an existing record.
    # Uses Familia's WATCH-based save_if_not_exists! so the exists-check
    # and save participate in the same optimistic transaction.
    #
    # @param domain_id [String] CustomDomain identifier
    # @param enabled   [Boolean, String] value to use only if creating
    # @return [Array(HomepageConfig, Symbol)] [config, :created | :existed]
    def find_or_create_for_domain(domain_id:, enabled:, signup_enabled: nil, signin_enabled: nil)
      raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?

      existing = find_by_domain_id(domain_id)
      return [existing, :existed] if existing

      now    = Familia.now.to_i
      config = new(
        domain_id: domain_id,
        enabled: enabled.to_s,
        signup_enabled: signup_enabled.nil? ? false : signup_enabled,
        signin_enabled: signin_enabled.nil? ? false : signin_enabled,
        secrets_mode: DEFAULT_SECRETS_MODE,
        created: now,
        updated: now,
      )

      begin
        config.save_if_not_exists!
        [config, :created]
      rescue Familia::RecordExistsError
        # A racing writer's record existed inside Familia's WATCH block.
        # Re-read must succeed: if it doesn't, the record vanished between
        # WATCH and re-read (concurrent destroy, TTL eviction, test teardown).
        # Raise rather than silently return [nil, :existed] and break the
        # method contract.
        found = find_by_domain_id(domain_id)
        raise Onetime::Problem, "HomepageConfig for #{domain_id} vanished after conflict" unless found

        [found, :existed]
      end
    end

    # Create a new homepage config for a domain.
    #
    # @param domain_id [String] CustomDomain identifier
    # @param attrs [Hash] Configuration attributes
    # @return [CustomDomain::HomepageConfig] The created config
    # @raise [Onetime::Problem] if config already exists
    def create!(domain_id:, **attrs)
      raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
      raise Onetime::Problem, 'Homepage config already exists for this domain' if exists_for_domain?(domain_id)

      config = new(domain_id: domain_id)

      config.enabled        = attrs[:enabled].to_s if attrs.key?(:enabled)
      config.signup_enabled = attrs[:signup_enabled] if attrs.key?(:signup_enabled)
      config.signin_enabled = attrs[:signin_enabled] if attrs.key?(:signin_enabled)
      if attrs.key?(:disabled_homepage_variant)
        config.disabled_homepage_variant = coerce_disabled_homepage_variant(attrs[:disabled_homepage_variant])
      end
      config.secrets_mode   = coerce_secrets_mode(attrs[:secrets_mode]) if attrs.key?(:secrets_mode)
      # Validating setters (InvalidCidr / TooManyCidrs raise before save).
      config.allowed_cidrs  = attrs[:allowed_cidrs] if attrs.key?(:allowed_cidrs)
      config.denied_cidrs   = attrs[:denied_cidrs] if attrs.key?(:denied_cidrs)

      now            = Familia.now.to_i
      config.created = now
      config.updated = now

      config.save
      config
    end

    # Delete homepage config for a domain.
    #
    # @param domain_id [String] CustomDomain identifier
    # @return [Boolean] true if deleted, false if not found
    def delete_for_domain!(domain_id)
      return false if domain_id.to_s.empty?

      config = find_by_domain_id(domain_id)
      return false unless config

      config.destroy!
      true
    end
  end
end
