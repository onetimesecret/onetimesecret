# lib/onetime/config.rb
#
# frozen_string_literal: true

require 'date' # ensure Date/Time constants resolve for permitted_classes
require 'json' # String#to_json for YAML-safe BRAND_* interpolation (see brand block)
require_relative 'utils/config_resolver'
require_relative 'utils/enumerables'

module Onetime
  # Loads, merges, and normalizes the YAML/ENV configuration.
  #
  # ## Changing the config surface
  #
  # The config shape is mirrored in several places that drift silently. When you
  # add, rename, or remove a config key or its backing BRAND_*/ENV var, update
  # all four in the same change:
  #
  #   1. etc/defaults/config.defaults.yaml — the shipped default and its ENV wiring.
  #   2. Zod contracts under src/schemas/contracts/config/ (and the flattened
  #      bootstrap payload in src/schemas/contracts/bootstrap.ts) so the frontend
  #      validates the new shape.
  #   3. DEPRECATIONS (below) — add an entry when a key or ENV var is removed or
  #      relocated, so boot warns/raises per compatibility.deprecated_config_mode.
  #   4. docs/architecture/*.md and .env.reference — keep the operator-facing docs
  #      and the ENV reference in sync.
  module Config
    extend self

    using Familia::Refinements::TimeLiterals

    unless defined?(SERVICE_PATHS)
      SERVICE_PATHS = %w[/etc/onetime ./etc ./etc/defaults].freeze
      UTILITY_PATHS = %w[~/.onetime /etc/onetime ./etc ./etc/defaults].freeze
      DEFAULTS      = {
        'site' => {
          'secret' => nil,
          'secret_options' => {
            'default_ttl' => 7.days,
            # These DEFAULTS are the effective values when the YAML config
            # sets ttl_options to nil (e.g. no TTL_OPTIONS env var). The
            # deep_merge nil-preservation rule means nil in YAML keeps
            # this array intact. The max here (30.days) becomes the global
            # TTL ceiling — override via TTL_OPTIONS env var in production
            # if a lower cap is needed.
            'ttl_options' => [
              60.seconds,     # 60 seconds (was missing from v0.20.5)
              5.minutes,      # 300 seconds
              30.minutes,     # 1800
              1.hour,         # 3600
              4.hours,        # 14400
              12.hours,       # 43200
              1.day,          # 86400
              3.days,         # 259200
              1.week,         # 604800
              2.weeks,        # 1209600
              30.days,        # 2592000
            ],
            'passphrase' => {
              'required' => false,
              'minimum_length' => 4,
              'maximum_length' => 128,
              'enforce_complexity' => false,
            },
            # Limits on the secret content itself. maximum_length is the
            # server-enforced ceiling on secret body size and the single
            # source of truth for the client-side textarea hint (exposed via
            # public config as secret_options.content.maximum_length).
            'content' => {
              'maximum_length' => 10_000,
            },
            'password_generation' => {
              'default_length' => 12,
              'length_options' => [8, 12, 16, 20, 24, 32],
              'character_sets' => {
                'uppercase' => true,
                'lowercase' => true,
                'numbers' => true,
                'symbols' => false,
                'exclude_ambiguous' => true,
              },
            },
          },
          'interface' => {
            'ui' => { 'enabled' => true },
            'api' => {
              'enabled' => true,
              'guest_routes' => {
                'enabled' => true,
                'conceal' => true,
                'generate' => true,
                'reveal' => true,
                'burn' => true,
                'show' => true,
                'receipt' => true,
              },
            },
          },
          # All keys that we want to explicitly be set to false when enabled
          # is false, should be represented in this hash.
          'authentication' => {
            'enabled' => false,
            'signin' => false,
            'signup' => false,
            'autoverify' => false,
            'allowed_signup_domains' => [],
          },
          # Colonel admin surfaces network posture. allowed_cidrs empty (default)
          # = AdminNetworkIsolation middleware is a no-op; both /colonel and
          # /api/colonel stay reachable, gated only by the two app-layer auth
          # layers. Set to private CIDRs on cloud to require an in-network
          # (VPN/private) origin as defense-in-depth. See
          # lib/onetime/middleware/admin_network_isolation.rb.
          'admin' => {
            'allowed_cidrs' => [],
          },
        },
        'features' => {
          'regions' => { 'enabled' => false },
          'domains' => {
            'enabled' => false,
            # When true, secret creation against an unverified custom
            # share_domain raises a form error. When false (default),
            # creation is allowed regardless of the domain's verification
            # status. Canonical domains are unaffected.
            'require_verified' => false,
          },
          'incoming' => {
            'enabled' => false,
            'memo_max_length' => 50,
            'default_ttl' => 604_800, # 7 days
            'default_passphrase' => nil,
            'recipients' => [],
          },
        },
        'internationalization' => {
          'enabled' => false,
          'default_locale' => 'en',
          'date_format' => 'locale',
          'datetime_format' => 'locale',
        },
        'mail' => {},
        'diagnostics' => {
          'enabled' => false,
        },
        'development' => {
          'enabled' => false,
          'frontend_host' => '',
          'allow_nil_global_secret' => false, # defaults to a secure setting
        },
        'compatibility' => {
          # How the boot process responds when a deprecated config key or
          # env var is detected: 'strict' raises OT::ConfigError, 'warn'
          # logs and continues, 'silent' ignores. See DEPRECATIONS.
          'deprecated_config_mode' => 'strict',
        },
        'experimental' => {
          # Opt-in, not-yet-stable feature flags. Each flag is safe to disable
          # at any time (rollback is a config flip); flags graduate out of this
          # section once stable. Present here as a defensive default so the key
          # always resolves even when a deployment's YAML omits the section.
          #
          # Currently empty: the Colonel admin-console cutover flag was retired
          # once the rebuilt console became the sole admin frontend. See
          # docs/specs/colonel-ui/50-cutover-hardening.md.
        },
      }

      # Declarative manifest of removed and deprecated configuration keys.
      #
      # Each entry maps a deprecated config path and/or the env var that
      # used to populate it to a migration message. check_deprecations
      # scans these at boot; compatibility.deprecated_config_mode decides
      # whether a match raises OT::ConfigError ('strict'), logs ('warn'),
      # or is ignored ('silent').
      #
      # Fields:
      #   path:     Array of keys to dig into conf (optional)
      #   env:      Environment variable name (optional)
      #   trigger:  Proc that receives the path value; returns true to fire (optional)
      #             When absent, any non-nil value triggers. Use for type-specific checks.
      #   severity: :warn marks a soft deprecation — the legacy value still works
      #             (via a fallback shim), so detection only ever logs, even under
      #             the 'strict' policy ('silent' still suppresses it). Entries
      #             without severity describe removed keys and follow the policy
      #             as-is, raising under 'strict'.
      #   message:  User-facing migration guidance
      DEPRECATIONS = [
        {
          path: %w[site interface ui homepage trusted_proxy_depth],
          env: 'UI_HOMEPAGE_TRUSTED_PROXY_DEPTH',
          message: <<~MSG.chomp,
            site.interface.ui.homepage.trusted_proxy_depth is ignored. Configure proxy
            depth globally via site.network.trusted_proxy (TRUSTED_PROXY_ENABLED,
            TRUSTED_PROXY_MODE=depth, TRUSTED_PROXY_DEPTH).
          MSG
        },
        {
          path: %w[site interface ui homepage trusted_ip_header],
          env: 'UI_HOMEPAGE_TRUSTED_IP_HEADER',
          message: <<~MSG.chomp,
            site.interface.ui.homepage.trusted_ip_header is ignored. Configure the
            forwarding header globally via site.network.trusted_proxy.header
            (TRUSTED_PROXY_HEADER).
          MSG
        },
        {
          path: %w[site domains],
          env: nil,
          message: <<~MSG.chomp,
            site.domains is ignored. This config moved to features.domains;
            only the new path is read.
          MSG
        },
        {
          path: %w[site regions],
          env: nil,
          message: <<~MSG.chomp,
            site.regions is ignored. This config moved to features.regions;
            only the new path is read.
          MSG
        },
        {
          path: %w[features regions jurisdictions],
          env: nil,
          # Only trigger on Array (old YAML format), not String (new ENV format)
          trigger: ->(value) { value.is_a?(Array) },
          message: <<~MSG.chomp,
            features.regions.jurisdictions array format is deprecated. Use JURISDICTIONS env var
            (format: EU:eu.example.com,CA:ca.example.com) instead.
          MSG
        },
        # Brand identity consolidation (#3612): the brand: block is the single
        # authority for brand identity. The legacy header.branding path and its
        # unprefixed env vars still work via normalize_brand fallbacks, so these
        # are soft (severity: :warn) — boot warns with the one-line fix but
        # never refuses to start a working install.
        {
          env: 'SITE_NAME',
          severity: :warn,
          message: <<~MSG.chomp,
            SITE_NAME is deprecated. Set BRAND_PRODUCT_NAME (brand.product_name) instead;
            the SITE_NAME value is honored as a fallback for now.
          MSG
        },
        {
          env: 'LOGO_URL',
          severity: :warn,
          message: <<~MSG.chomp,
            LOGO_URL is deprecated. Set BRAND_LOGO_URL (brand.logo_url) instead;
            the LOGO_URL value is honored as a fallback for now.
          MSG
        },
        {
          env: 'LOGO_ALT',
          severity: :warn,
          message: <<~MSG.chomp,
            LOGO_ALT is deprecated. Set BRAND_LOGO_ALT (brand.logo_alt) instead;
            the LOGO_ALT value is honored as a fallback for now.
          MSG
        },
        {
          path: %w[site interface ui header branding],
          env: nil,
          severity: :warn,
          message: <<~MSG.chomp,
            site.interface.ui.header.branding is deprecated. Brand identity moved to the
            brand: block (BRAND_PRODUCT_NAME, BRAND_LOGO_URL, BRAND_LOGO_ALT); masthead
            layout knobs moved to site.interface.ui.header.logo (href, show_name,
            prominent — LOGO_LINK, LOGO_SHOW_NAME, LOGO_PROMINENT are unchanged).
            Legacy values are honored as fallbacks for now.
          MSG
        },
      ].freeze

    end

    attr_reader :env, :base, :bootstrap
    attr_writer :path

    # Normalizes environment variables prior to loading and rendering the YAML
    # configuration. In some cases, this might include setting default values
    # and ensuring necessary environment variables are present.
    def before_load
      # In v0.20.6, REGIONS_ENABLE was renamed to REGIONS_ENABLED for
      # consistency. We ensure both are considered for compatability.
      ENV['REGIONS_ENABLED'] = ENV.values_at('REGIONS_ENABLED', 'REGIONS_ENABLE').compact.first || 'false'
    end

    # Load a YAML configuration file with layered defaults support.
    #
    # When etc/defaults/config.defaults.yaml exists, it is loaded first as
    # the base layer. The environment-specific file (from +path+) is then
    # deep-merged on top so overrides win. This ensures sections defined
    # only in the defaults file are visible in all environments without
    # manual duplication. See #3322.
    #
    # The YAML layer merge uses preserve_nils: false so that explicit nil
    # in the environment file means "I want nil" (not "keep the default").
    # Nil-preservation is reserved for the in-code DEFAULTS merge in
    # after_load, where nil means "not specified".
    #
    # @param path [String] (optional) path to the environment-specific YAML
    #   file. When nil, layered defaults are applied automatically. When an
    #   explicit path is given, only that file is loaded (no defaults layer).
    # @return [Hash] the parsed, merged YAML data
    #
    def load(path = nil)
      using_default_path = path.nil?
      path             ||= self.path
      loading_file       = path

      if path.nil? || path.empty?
        raise ArgumentError, 'Config path not set (checked etc/config.yaml and SERVICE_PATHS)'
      end

      unless File.readable?(path)
        raise ArgumentError, "Config not readable: #{path}"
      end

      base_config = if using_default_path
        defaults_file = Onetime::Utils::ConfigResolver.defaults_path('config')
        if defaults_file && defaults_file != path
          loading_file = defaults_file # track for rescue reporting
          load_yaml_with_erb(defaults_file)
        else
          {}
        end
      else
        {}
      end

      loading_file = path
      env_config   = load_yaml_with_erb(path)

      if base_config.empty?
        env_config
      else
        Onetime::Utils::Enumerables.deep_merge(base_config, env_config, preserve_nils: false)
      end
    rescue StandardError => ex
      OT.le "Error loading config: #{loading_file}"

      if OT.debug?
        begin
          template_lines = File.read(loading_file).split("\n")
          template_lines.each_with_index do |line, index|
            OT.ld "Line #{index + 1}: #{line}"
          end
        rescue StandardError => debug_ex
          OT.ld "Could not read template for debug output: #{debug_ex.message}"
        end
      end

      OT.le ex.message
      OT.le ex.backtrace.join("\n")
      raise OT::ConfigError.new(ex.message)
    end

    def load_yaml_with_erb(path)
      parsed_template = ERB.new(File.read(path))
      # Use safe_load so a malicious config file cannot instantiate arbitrary
      # Ruby objects (!ruby/object). Symbol is permitted because config keys
      # and values use symbols. Date and Time are permitted so an unquoted
      # date/time in a deployment's config (e.g. `expires: 2026-01-02`) loads
      # as a Date/Time instance rather than raising Psych::DisallowedClass and
      # breaking boot (per issue #3498's recommendation). aliases: true keeps
      # anchors/aliases working, matching the config validator
      # (operations/config/validate.rb) so a config that validates also boots;
      # the validator's permitted_classes are kept in sync with this list.
      YAML.safe_load(parsed_template.result, permitted_classes: [Symbol, Date, Time], aliases: true) || {}
    end
    private :load_yaml_with_erb

    # Coerce a TTL config value to Integer seconds, failing loud on a date/time.
    # safe_load permits Date/Time (#3498) so unquoted dates in *other* fields
    # don't break boot, but a date/time in a numeric TTL field is a quoting
    # mistake: Date#to_i raises NoMethodError, and Time#to_i silently yields a
    # ~56yr TTL. Reject both with an actionable error; String/Float still coerce.
    def coerce_ttl_seconds(value, field)
      return value if value.is_a?(Integer)

      if value.is_a?(Date) || value.is_a?(Time)
        raise OT::ConfigError,
          "#{field} must be a number of seconds, not a date/time (#{value.inspect}); " \
          'quote the value or use integer seconds'
      end

      value.to_i
    end
    private :coerce_ttl_seconds

    # After loading the configuration, this method processes and validates the
    # configuration, setting defaults and ensuring required elements are present.
    # It also performs deep copy protection to prevent mutations from propagating
    # to shared configuration instances.
    #
    # @param loaded_config [Hash] The loaded, unprocessed configuration hash in raw form
    # @return [Hash] The processed configuration hash with defaults applied and security measures in place
    def after_load(loaded_config)
      # SAFETY MEASURE: Deep Copy Protection
      # Create a deep copy of the configuration to prevent unintended mutations
      # This protects against side effects when multiple components access the same config
      # Without this, modifications to the config in one component could affect others.
      conf = if loaded_config.nil?
        {}
      else
        deep_clone(loaded_config)
      end

      # SAFETY MEASURE: Validation and Default Security Settings
      # Ensure all critical security-related configurations exist
      conf = deep_merge(DEFAULTS, conf) # TODO: We don't need to re-assign `conf`

      raise_concerns(conf)

      # MIGRATION VALIDATION: Detect deprecated configuration keys / env vars
      # and respond per compatibility.deprecated_config_mode.
      # Must run BEFORE jurisdiction parsing so trigger proc sees original type.
      check_deprecations(conf)

      # Parse jurisdictions from string env var format AFTER deprecation check.
      # Format: "EU:eu.example.com,CA:ca.example.com" -> array of hashes
      # The trigger proc above only fires on Array (old YAML format), not String.
      jurisdictions = conf.dig('features', 'regions', 'jurisdictions')
      if jurisdictions.is_a?(String) && !jurisdictions.empty?
        entries                                      = jurisdictions.split(',').map(&:strip).reject(&:empty?)
        conf['features']['regions']['jurisdictions'] = entries.map do |entry|
          identifier, domain = entry.split(':', 2).map(&:strip)
          if identifier.empty? || domain.to_s.empty?
            raise OT::ConfigError, "Invalid JURISDICTIONS format: '#{entry}' (expected ID:domain)"
          end

          {
            'identifier' => identifier,
            'domain' => domain,
            'display_name_i18n_key' => "web.regions.jurisdictions.#{identifier.downcase}.name",
          }
        end
      elsif jurisdictions.is_a?(String) || jurisdictions.nil?
        # Empty string or nil -> empty array
        conf['features']['regions']['jurisdictions'] = []
      end

      # Disable all authentication sub-features when main feature is off for
      # consistency, security, and to prevent unexpected behavior. Ensures clean
      # config state.
      # NOTE: Needs to run after other site.authentication logic
      if conf.dig('site', 'authentication', 'enabled') != true
        conf['site']['authentication'].each_key do |key|
          conf['site']['authentication'][key] = false
        end
      end

      ttl_options = conf.dig('site', 'secret_options', 'ttl_options')
      default_ttl = conf.dig('site', 'secret_options', 'default_ttl')

      # if the ttl_options setting is a string, we want to split it into an
      # array of integers.
      if ttl_options.is_a?(String)
        conf['site']['secret_options']['ttl_options'] = ttl_options.split(/\s+/)
      end
      ttl_options = conf.dig('site', 'secret_options', 'ttl_options')
      if ttl_options.is_a?(Array)
        conf['site']['secret_options']['ttl_options'] = ttl_options.map(&:to_i)
      end

      # Coerce to Integer seconds. YAML loads a bare `604800.0` as Float and ERB
      # returns String when an env var is set; both must become Integer seconds
      # before reaching spawn_pair (#3299). safe_load also permits Date/Time
      # (#3498), so coerce_ttl_seconds rejects a date/time literal here rather
      # than crashing (Date#to_i) or silently minting a ~56yr TTL (Time#to_i).
      unless default_ttl.nil?
        conf['site']['secret_options']['default_ttl'] =
          coerce_ttl_seconds(default_ttl, 'site.secret_options.default_ttl')
      end

      # Confirmed leak path (#3299): features.incoming.default_ttl is set from
      # `ENV['INCOMING_DEFAULT_TTL'] || 604800`, so a set env var yields a String
      # that flows uncoerced through recipient_resolver -> create_incoming_secret
      # -> spawn_pair. Normalize it the same way as the site default.
      incoming_ttl = conf.dig('features', 'incoming', 'default_ttl')
      unless incoming_ttl.nil?
        conf['features']['incoming']['default_ttl'] =
          coerce_ttl_seconds(incoming_ttl, 'features.incoming.default_ttl')
      end

      # Process passphrase configuration
      passphrase_config = conf.dig('site', 'secret_options', 'passphrase') || {}

      if passphrase_config['minimum_length'].is_a?(String)
        conf['site']['secret_options']['passphrase']['minimum_length'] = passphrase_config['minimum_length'].to_i
      end

      if passphrase_config['maximum_length'].is_a?(String)
        conf['site']['secret_options']['passphrase']['maximum_length'] = passphrase_config['maximum_length'].to_i
      end

      # Process secret content limits. ENV/ERB delivers strings and unquoted
      # YAML scalars like 10000.0 parse as Float; normalize any non-Integer to
      # an Integer so the value the frontend receives satisfies its int()
      # contract and never renders as "10000.0".
      content_config = conf.dig('site', 'secret_options', 'content') || {}
      content_max    = content_config['maximum_length']
      unless content_max.nil? || content_max.is_a?(Integer)
        conf['site']['secret_options']['content']['maximum_length'] = content_max.to_i
      end

      # Process password generation configuration
      password_gen_config = conf.dig('site', 'secret_options', 'password_generation') || {}

      if password_gen_config['default_length'].is_a?(String)
        conf['site']['secret_options']['password_generation']['default_length'] = password_gen_config['default_length'].to_i
      end

      # Handle length_options as string or array
      length_options = password_gen_config['length_options']
      if length_options.is_a?(String)
        conf['site']['secret_options']['password_generation']['length_options'] = length_options.split(/\s+/).map(&:to_i)
      elsif length_options.is_a?(Array)
        conf['site']['secret_options']['password_generation']['length_options'] = length_options.map(&:to_i)
      end

      # Normalize the brand block from BRAND_* env vars. Done here (in Ruby)
      # rather than via ERB/YAML interpolation so values with YAML-significant
      # characters — notably the leading '#' in primary_color hex — survive.
      # Runs after check_deprecations (so legacy branding config is reported
      # before its values are absorbed) and before deep_freeze (so consumers
      # never resolve fallbacks themselves). normalize_header_layout must
      # follow normalize_brand: it deletes the legacy branding subtree that
      # normalize_brand's fallbacks read.
      normalize_brand(conf)
      normalize_header_layout(conf)

      # Ensure array jurisdiction entries have display_name_i18n_key
      # (String format already converted to Array above, before check_deprecations)
      jurisdictions = conf.dig('features', 'regions', 'jurisdictions')
      if jurisdictions.is_a?(Array)
        conf['features']['regions']['jurisdictions'] = jurisdictions.map do |j|
          j                            = j.dup if j.frozen?
          j['display_name_i18n_key'] ||= "web.regions.jurisdictions.#{j['identifier'].to_s.downcase}.name"
          j
        end
      end

      # Apply the defaults to sentry backend and frontend configs
      # and set our local config with the merged values.
      diagnostics                                = loaded_config.fetch('diagnostics', {})
      conf['diagnostics']                        = {
        'enabled' => diagnostics['enabled'] || false,
        'sentry' => apply_defaults_to_peers(diagnostics['sentry']),
      }
      conf['diagnostics']['sentry']['backend'] ||= {}

      # Update global diagnostic flag based on config
      backend_dsn  = conf.dig('diagnostics', 'sentry', 'backend', 'dsn')
      frontend_dsn = conf.dig('diagnostics', 'sentry', 'frontend', 'dsn')

      # It's disabled when no DSN is present, regardless of enabled setting
      Onetime.d9s_enabled = !!(conf.dig('diagnostics', 'enabled') && (backend_dsn || frontend_dsn))

      # SECURITY MEASURE #4: Configuration Immutability
      # Freeze the entire configuration recursively to prevent modifications
      # This ensures configuration immutability and protects against
      # accidental or malicious changes after loading
      #
      # Why this matters:
      # - Prevents runtime modification of sensitive values like secrets and API keys
      # - Any attempt to modify frozen config will raise a FrozenError, failing fast
      # - Guarantees configuration integrity throughout application lifecycle
      # - Makes security guarantees stronger by ensuring config values can't be tampered with
      #
      # Skip freezing in test mode to allow config modifications for test isolation.
      # Tests may need to modify config values without triggering FrozenError.
      # See also: boot.rb line 133 which guards the raw_conf freeze.
      deep_freeze(conf) unless OT.testing?
      conf
    end

    # Maps each brand config key to its backing env var. String fields are
    # trimmed (empty -> nil); button_text_light is coerced to a real boolean.
    BRAND_ENV = {
      'primary_color' => 'BRAND_PRIMARY_COLOR',
      'product_name' => 'BRAND_PRODUCT_NAME',
      'product_domain' => 'BRAND_PRODUCT_DOMAIN',
      'support_email' => 'BRAND_SUPPORT_EMAIL',
      'signature_name' => 'BRAND_SIGNATURE_NAME',
      'corner_style' => 'BRAND_CORNER_STYLE',
      'font_family' => 'BRAND_FONT_FAMILY',
      'logo_url' => 'BRAND_LOGO_URL',
      'logo_alt' => 'BRAND_LOGO_ALT',
      'favicon_url' => 'BRAND_FAVICON_URL',
      'apple_touch_icon_url' => 'BRAND_APPLE_TOUCH_ICON_URL',
      'og_image_url' => 'BRAND_OG_IMAGE_URL',
      'totp_issuer' => 'BRAND_TOTP_ISSUER',
    }.freeze

    # Maps brand identity keys to their deprecated sources (#3612): the legacy
    # unprefixed env var and the legacy site.interface.ui.header.branding YAML
    # path. Consulted by normalize_brand only when the brand: authority (BRAND_*
    # env or brand: YAML) leaves the key nil, so working installs keep working
    # while check_deprecations names the one-line fix.
    LEGACY_BRAND_FALLBACKS = {
      'product_name' => {
        env: 'SITE_NAME',
        path: %w[site interface ui header branding site_name],
      },
      'logo_url' => {
        env: 'LOGO_URL',
        path: %w[site interface ui header branding logo url],
      },
      'logo_alt' => {
        env: 'LOGO_ALT',
        path: %w[site interface ui header branding logo alt],
      },
    }.freeze

    # Masthead layout knobs that moved from the legacy branding nesting to
    # site.interface.ui.header.logo (#3612). New-path key => legacy key under
    # header.branding.logo. Booleans are honored as-is; href replaces link_to.
    LEGACY_HEADER_LOGO_KEYS = {
      'href' => 'link_to',
      'show_name' => 'show_name',
      'prominent' => 'prominent',
    }.freeze

    # Normalize the brand block, reading BRAND_* env vars directly so values
    # containing YAML-significant characters (e.g. the '#' of a hex color)
    # are not mangled by the ERB/YAML layer. An env var that is set always
    # wins; when unset, the value already present from YAML is left intact so
    # operators can still set brand keys directly in their config file.
    #
    # Identity keys with a legacy source (LEGACY_BRAND_FALLBACKS) fall back to
    # the deprecated env var / header.branding path when the brand: authority
    # leaves them nil. Sentinel component values (e.g. the legacy LOGO_URL
    # default 'DefaultLogo.vue') are never adopted — they are frontend-only
    # markers, not asset URLs, and would break consumers like email templates.
    #
    # All resolution happens here, before the config is deep-frozen, so
    # consumers only ever read final values (never re-derive fallbacks).
    #
    # @param conf [Hash] the merged configuration (mutated in place)
    # @return [void]
    def normalize_brand(conf)
      brand = (conf['brand'] ||= {})

      BRAND_ENV.each do |key, env|
        raw = ENV.fetch(env, nil)
        if raw.nil?
          # Env not set: keep any YAML-supplied value, normalizing blanks to nil.
          existing   = brand[key]
          brand[key] = nil if existing.is_a?(String) && existing.strip.empty?
        else
          value      = raw.strip
          brand[key] = value.empty? ? nil : value
        end
      end

      # The logo asset must be an image URL: a Vue component reference (the
      # frontend's neutral-sentinel convention) is meaningless to emails,
      # favicon handling, and per-domain defaults, so it never enters the
      # brand block — from any source, including an operator-set
      # BRAND_LOGO_URL (hazard 1 of #3612).
      brand['logo_url'] = nil if brand['logo_url'].is_a?(String) && brand['logo_url'].end_with?('.vue')

      LEGACY_BRAND_FALLBACKS.each do |key, legacy|
        next unless brand[key].nil?

        candidate  = legacy_brand_value(ENV.fetch(legacy[:env], nil)) ||
                     legacy_brand_value(dig_path(conf, legacy[:path]))
        brand[key] = candidate if candidate
      end

      # A bare-relative logo path (e.g. 'img/logo.svg') resolves against the
      # browser's current-route directory, so it loads on '/' but 404s on a
      # nested route like '/receipt/:id' (the img then renders its alt text
      # instead). Root-relativize it here so the one install logo resolves
      # identically on every surface. Absolute URLs (scheme: or protocol-
      # relative //) and already-root-relative paths pass through untouched.
      logo_path = brand['logo_url']
      if logo_path.is_a?(String) && !logo_path.empty? &&
         !logo_path.start_with?('/') &&
         !logo_path.match?(/\A[a-z][a-z0-9+.-]*:/i)
        brand['logo_url'] = "/#{logo_path}"
      end

      # brand.logo_url is now the one install logo for every surface, but the
      # surfaces differ: the web UI resolves a relative path fine, while mail
      # rendering requires an absolute URL and silently degrades to a
      # text-only header otherwise. Tell the operator at boot rather than
      # letting them discover it in a delivered email. Deliberately always
      # logged: this is an operational notice about mail rendering, not a
      # deprecation, so compatibility.deprecated_config_mode does not apply.
      logo_url = brand['logo_url']
      if logo_url && !logo_url.match?(%r{\Ahttps?://}i)
        OT.le "CONFIG NOTICE: brand.logo_url '#{logo_url}' is not an absolute http(s) URL; " \
              'it will render in the web UI but is omitted from outbound emails.'
      end

      # button_text_light: light text on brand-colored buttons. Default-on;
      # only an explicit 'false' (env or YAML) disables it. nil when unset.
      raw                        = ENV.fetch('BRAND_BUTTON_TEXT_LIGHT', nil)
      brand['button_text_light'] = if raw.nil?
        case brand['button_text_light']
        when nil then nil
        when true, false then brand['button_text_light']
        else brand['button_text_light'].to_s != 'false'
        end
      elsif raw.strip.empty?
        nil
      else
        raw.strip != 'false'
      end
    end

    # Digs a key path out of a config hash, tolerating malformed intermediate
    # nodes: a legacy subtree where e.g. header.branding.logo is a scalar
    # would make Hash#dig raise TypeError (or NoMethodError, depending on the
    # node) and abort boot — for an optional fallback source, unreadable
    # simply means absent.
    #
    # @param conf [Hash] configuration hash
    # @param path [Array<String>] key path
    # @return [Object, nil]
    def dig_path(conf, path)
      conf.dig(*path)
    rescue TypeError, NoMethodError
      nil
    end

    # Normalizes a candidate value from a legacy branding source: trims,
    # rejects blanks and non-strings, and rejects Vue component sentinels
    # ('*.vue') so 'DefaultLogo.vue' never enters brand.logo_url (#3612).
    #
    # @param value [Object] raw legacy env var or YAML value
    # @return [String, nil] usable value or nil
    def legacy_brand_value(value)
      return nil unless value.is_a?(String)

      value = value.strip
      return nil if value.empty? || value.end_with?('.vue')

      value
    end

    # Migrates masthead layout knobs from the deprecated header.branding.logo
    # nesting to site.interface.ui.header.logo (#3612), then removes the
    # branding subtree so it never reaches the frontend bootstrap payload.
    # Legacy values only fill knobs the new path leaves nil (env vars LOGO_LINK
    # / LOGO_SHOW_NAME / LOGO_PROMINENT feed the new path via ERB already).
    # Identity fields under branding (logo.url/.alt, site_name) are harvested
    # by normalize_brand, which must run first.
    #
    # @param conf [Hash] the merged configuration (mutated in place)
    # @return [void]
    def normalize_header_layout(conf)
      header = conf.dig('site', 'interface', 'ui', 'header')
      return unless header.is_a?(Hash)

      branding    = header.delete('branding')
      legacy_logo = branding.is_a?(Hash) ? branding['logo'] : nil
      return unless legacy_logo.is_a?(Hash)

      # Coerce a malformed scalar (e.g. `logo: "oops"`) to an empty hash —
      # this path exists to tolerate legacy/hand-edited configs, so it must
      # not abort boot on one.
      logo = header['logo']
      logo = header['logo'] = {} unless logo.is_a?(Hash)
      LEGACY_HEADER_LOGO_KEYS.each do |new_key, legacy_key|
        next if legacy_logo[legacy_key].nil? || !logo[new_key].nil?

        logo[new_key] = legacy_logo[legacy_key]
      end
    end

    def raise_concerns(conf)
      # SAFETY MEASURE: Critical Secret Validation
      # Handle potential nil global secret
      # The global secret is critical for encrypting/decrypting secrets
      # Running without a global secret is only permitted in exceptional cases
      # Enforce development-mode constraint: allow_nil_global_secret is
      # only effective when development.enabled is true. Normalize it here
      # before the config is frozen so runtime code can read it directly.
      if conf.dig('development', 'allow_nil_global_secret') && !conf.dig('development', 'enabled')
        OT.le 'CONFIG WARNING: development.allow_nil_global_secret=true ignored because development.enabled is false'
        conf['development']['allow_nil_global_secret'] = false
      end

      # ADR-024: development frontend mode (RACK_ENV=development) makes the app
      # proxy /dist/* to a Vite dev server. That is a source-editing workflow and
      # needs the frontend build toolchain, which only a source checkout has. A
      # deployment artifact — notably the production container image, whose
      # Dockerfile prunes node_modules — has no toolchain and cannot host or reach
      # a Vite server, so the proxy surfaces as a per-request 500. Refuse to boot
      # loudly instead of serving a container that silently 500s every asset.
      if conf.dig('development', 'enabled') && !frontend_dev_workflow_available?
        raise OT::ConfigError, <<~MSG.chomp
          development.enabled is true (RACK_ENV=#{ENV['RACK_ENV'].inspect}) but this build has no Vite frontend toolchain — it is a deployment artifact (e.g. the production container image) that serves pre-built assets and cannot host or proxy a Vite dev server (ADR-024).
            Fix one of:
              - Containers: serve the assets baked at build time — unset RACK_ENV or set RACK_ENV=production.
              - Frontend dev: run on the host where the toolchain lives (bin/dev), not the shipped image.
            Deliberately proxying to an external Vite? Set ONETIME_ALLOW_DEV_FRONTEND=true to bypass this guard.
        MSG
      end

      allow_nil     = conf.dig('development', 'allow_nil_global_secret') || false
      global_secret = conf.dig('site', 'secret') || nil
      global_secret = nil if global_secret.to_s.strip == 'CHANGEME'

      if global_secret.nil?
        unless allow_nil
          # Fast fail when global secret is nil and not explicitly allowed
          # This is a critical security check that prevents running without encryption
          raise OT::ConfigError, 'Global secret cannot be nil - set SECRET env var or site.secret in config'
        end

        # SAFETY MEASURE: Security Warnings for Dangerous Configurations
        # Security warning when proceeding with nil global secret
        # These warnings are prominently displayed to ensure administrators
        # understand the security implications of their configuration
        OT.li '!' * 50
        OT.li 'SECURITY WARNING: Running with nil global secret!'
        OT.li 'This configuration presents serious security risks:'
        OT.li '- Secret encryption will be compromised'
        OT.li '- Data cannot be properly protected'
        OT.li '- Only use during recovery or transition periods'
        OT.li 'Set valid SECRET env var or site.secret in config ASAP'
        OT.li '!' * 50
      end

      unless conf['mail'].key?('truemail')
        raise OT::ConfigError, 'No TrueMail config found'
      end
    end

    # True when this process can participate in the Vite dev-server workflow:
    # either the frontend build toolchain is present (a source checkout) or the
    # operator has explicitly opted into an external-Vite topology. Used to reject
    # development frontend mode on a deployment artifact at boot (ADR-024).
    #
    # @return [Boolean]
    def frontend_dev_workflow_available?
      return true if %w[1 true yes].include?(ENV['ONETIME_ALLOW_DEV_FRONTEND'].to_s.strip.downcase)

      home = ENV.fetch('ONETIME_HOME', '.')
      File.exist?(File.join(home, 'node_modules', '.bin', 'vite'))
    end

    # Detects deprecated configuration keys and environment variables.
    #
    # Scans the DEPRECATIONS manifest. A deprecation is considered present
    # when its config path resolves to a non-nil value, or its env var is
    # set to a non-empty value. The response is governed by
    # compatibility.deprecated_config_mode:
    #
    #   strict (default) - raise OT::ConfigError, refusing to boot
    #   warn             - log each migration message and continue
    #   silent           - ignore
    #
    # An unrecognized policy value is treated as strict. Entries marked
    # severity: :warn are soft deprecations (the legacy value still works
    # via a fallback shim): they log under both 'strict' and 'warn' and
    # never raise, so a working install keeps booting.
    #
    # @param conf [Hash] The merged configuration
    # @return [void]
    # @raise [OT::ConfigError] When a removed key is found under strict policy
    def check_deprecations(conf)
      detected = DEPRECATIONS.select do |dep|
        env_set = !!(dep[:env] && !ENV[dep[:env]].to_s.empty?)

        # Check path, optionally with a trigger proc for type-specific detection
        path_value = dep[:path] && dig_path(conf, dep[:path])
        path_set   = if dep[:trigger] && path_value
          dep[:trigger].call(path_value)
        else
          !path_value.nil?
        end

        env_set || path_set
      end
      return if detected.empty?

      policy = (conf.dig('compatibility', 'deprecated_config_mode') || 'strict').to_s
      return if policy == 'silent'

      soft, hard = detected.partition { |dep| dep[:severity] == :warn }
      soft.each { |dep| OT.le "CONFIG DEPRECATION: #{dep[:message]}" }
      return if hard.empty?

      messages = hard.map { |dep| dep[:message] }
      if policy == 'warn'
        messages.each { |msg| OT.le "CONFIG DEPRECATION: #{msg}" }
        return
      end

      raise OT::ConfigError,
        "Deprecated configuration detected:\n  - #{messages.join("\n  - ")}\n\n" \
        "Set compatibility.deprecated_config_mode (DEPRECATED_CONFIG_MODE) to 'warn' " \
        'to downgrade this to a logged warning.'
    end

    def dirname
      @dirname ||= File.dirname(path)
    end

    def path
      @path ||= Onetime::Utils::ConfigResolver.resolve('config') || find_configs.first
    end

    def mapped_key(key)
      # `key` is a string. Returns a string.
      # If the key is not in the KEY_MAP, return the key itself.
      KEY_MAP[key] || key
    end

    # Recursively freezes an object and all its nested components
    # to ensure complete immutability. This is a critical security
    # measure that prevents any modification of configuration values
    # after they've been loaded and validated, protecting against both
    # accidental mutations and potential security exploits.
    #
    # @param obj [Object] The object to freeze
    # @return [Object] The frozen object
    # @security This ensures configuration values cannot be tampered with at runtime
    def deep_freeze(obj)
      case obj
      when Hash
        obj.each_value { |v| deep_freeze(v) }
      when Array
        obj.each { |v| deep_freeze(v) }
      end
      obj.freeze
    end

    # Creates a complete deep copy of a configuration hash, preventing
    # unintended sharing of references that could let a mutation of one clone
    # corrupt another component's view of the config.
    #
    # Delegates to Onetime::Utils::Enumerables.deep_clone, the single hardened
    # implementation: a YAML.safe_load(YAML.dump(...)) round-trip that permits
    # only plain data types (no arbitrary Ruby objects). Config comes from
    # trusted local files, so we opt out of the serialized-size gate (max_size)
    # to preserve this path's historical unrestricted behavior for large
    # deployment configs.
    #
    # @param config_hash [Hash] The configuration hash to be cloned
    # @return [Hash] A deep copy of the original configuration hash
    # @raise [OT::Problem] When serialization fails
    # @security Prevents configuration mutations from affecting multiple components
    def deep_clone(config_hash)
      Onetime::Utils::Enumerables.deep_clone(config_hash, max_size: Float::INFINITY)
    end

    # Applies default values to its config level peers
    #
    # @param config [Hash] Configuration with top-level section keys, including a 'defaults' key
    # @return [Hash] Configuration with defaults applied to each section, with 'defaults' removed
    #
    # This method extracts defaults from the 'defaults' key and applies them to each section:
    # - Section values override defaults (except nil values, which use defaults)
    # - The 'defaults' section is removed from the result
    # - Only Hash-type sections receive defaults
    #
    # @example Basic usage
    #   config = {
    #     'defaults' => { 'timeout' => 5, 'enabled' => true },
    #     'api' => { 'timeout' => 10 },
    #     'web' => { 'theme' => 'dark' }
    #   }
    #   apply_defaults_to_peers(config)
    #   # => { 'api' => { 'timeout' => 10, 'enabled' => true },
    #   #      'web' => { 'theme' => 'dark', 'timeout' => 5, 'enabled' => true } }
    #
    # @example Edge cases
    #   apply_defaults_to_peers({'a' => {'x' => 1}})                # => {'a' => {'x' => 1}}
    #   apply_defaults_to_peers({'defaults' => {'x' => 1}, 'b' => {}})  # => {'b' => {'x' => 1}}
    #
    def apply_defaults_to_peers(config = {})
      return {} if config.nil? || config.empty?

      # Extract defaults from the configuration
      defaults = config['defaults']

      # If no valid defaults exist, return config without the 'defaults' key
      return config.except('defaults') unless defaults.is_a?(Hash)

      # Process each section, applying defaults
      config.each_with_object({}) do |(section, values), result|
        next if section == 'defaults'   # Skip the 'defaults' key
        next unless values.is_a?(Hash) # Process only sections that are hashes

        # Apply defaults to each section
        result[section] = deep_merge(defaults, values)
      end
    end

    # Searches for configuration files in predefined locations based on application mode.
    # In CLI mode, it looks in user and system directories. In service mode, it only
    # checks system directories for security and consistency.
    #
    # @param filename [String, nil] Optional configuration filename, defaults to 'config.yaml'
    # @return [Array<String>] List of found configuration file paths in order of precedence
    #
    # @example Finding default config files
    #   find_configs
    #   # => ["/etc/onetime/config.yaml"]
    #
    # @example Finding custom config files
    #   find_configs("database.yaml")
    #   # => ["/etc/onetime/database.yaml", "./etc/database.yaml"]
    def find_configs(filename = nil)
      filename ||= 'config.yaml'
      paths      = Onetime.mode?(:cli) ? UTILITY_PATHS : SERVICE_PATHS
      paths.collect do |path|
        f = File.join File.expand_path(path), filename
        Onetime.ld "[init] Looking for #{f}"
        f if File.exist?(f)
      end.compact
    end

    # Makes a deep copy of OT.conf, then merges the system settings data, and
    # replaces OT.config with the merged data.
    def apply_config(other)
      new_config = deep_merge(OT.conf, other)
      OT.replace_config! new_config
    end

    # Deep merge with nil-preservation semantics.
    #
    # When YAML config resolves a key to nil (e.g. `ttl_options: <%= nil %>`),
    # the DEFAULTS value is preserved — nil means "not specified", not "empty".
    # This is the v2.nil? branch below: if the loaded config has nil for a key,
    # the original (DEFAULTS) value wins.
    #
    # Consequence: DEFAULTS.ttl_options.max determines the effective TTL ceiling
    # unless the deployment explicitly sets TTL_OPTIONS. An empty string would
    # NOT trigger this preservation (it's truthy), so `ttl_options: ""` would
    # replace the array with "" — use nil, not empty string, to inherit defaults.
    #
    # @param original [Hash] Base hash with default values
    # @param other [Hash] Hash with values that override defaults
    # @return [Hash] A new hash containing the merged result
    def deep_merge(original, other)
      return deep_clone(other) if original.nil?
      return deep_clone(original) if other.nil?

      original_clone = deep_clone(original)
      other_clone    = deep_clone(other)
      merger         = proc do |_key, v1, v2|
        if v1.is_a?(Hash) && v2.is_a?(Hash)
          v1.merge(v2, &merger)
        elsif v2.nil?
          v1 # nil in loaded config = "not specified" → keep default
        else
          v2
        end
      end
      original_clone.merge(other_clone, &merger)
    end
  end

  # A simple map of our config options using our naming conventions
  # to the names that are used by other libraries. This makes it easier
  # for us to have our own consistent naming conventions.
  unless defined?(KEY_MAP)
    KEY_MAP = {
      # NOTE: validation_type_for is NOT mapped because it's the correct setter name
      # in Truemail. The getter is validation_type_by_domain (asymmetric API).
      'allowed_domains_only' => 'whitelist_validation',
      'allowed_emails' => 'whitelisted_emails',
      'blocked_emails' => 'blacklisted_emails',
      'allowed_domains' => 'whitelisted_domains',
      'blocked_domains' => 'blacklisted_domains',
      'blocked_mx_ip_addresses' => 'blacklisted_mx_ip_addresses',

      # An example mapping for testing.
      'example_internal_key' => 'example_external_key',
    }
  end
end
