# lib/onetime/models/custom_domain/signin_config.rb
#
# frozen_string_literal: true

require_relative '../features/boolean_encoding'

#
# CustomDomain::SigninConfig - Per-domain sign-in method configuration
#
# This model stores sign-in policy configuration bound to a specific CustomDomain.
# Enables per-tenant control over which authentication methods are available
# on the login page.
#
# Use Cases:
#   - SSO-only enforcement: secrets.corp.com restricts to SSO login
#   - Passwordless: secrets.modern.com restricts to email_auth (magic links)
#   - Method isolation: hide methods that aren't relevant for a domain's users
#
# Non-Nullable Override Semantics:
#   All boolean fields are non-nullable with conservative defaults (false).
#   The `enabled` master switch gates whether this config is consulted at
#   all — when off, runtime resolution falls back to global. This is the
#   safety mechanism: creating a record never changes behavior until an
#   admin explicitly enables it and sets the fields they want.
#   When an admin configures a domain, the config they see is the config
#   that runs — no invisible inheritance from install-level defaults.
#
#   The install-level kill switch still wins: an enabled config can only
#   NARROW availability, never re-enable sign-in that is disabled globally
#   (AUTH_ENABLED / AUTH_SIGNIN). Field-level values are taken from the
#   config as-is (no inheritance), but the global capability gates the
#   result. See `resolve_signin_enabled`.
#
# Scope Boundary:
#   Install-wide security posture (MFA, lockout, password_requirements,
#   active_sessions) is NOT overridable per domain. Those are infrastructure,
#   not tenant configuration.
#
# See: lib/onetime/auth_config.rb (AuthConfig, restrict_to logic)
#      etc/defaults/auth.defaults.yaml (install-level defaults)
#      docs/architecture/decision-records/adr-024-custom-domain-auth-override-resolution.md
#      (source of truth for the two-flag model, resolution invariants, and the
#      settings API/UI contract built on them)
#
module Onetime
  class CustomDomain < Familia::Horreum
    class SigninConfig < Familia::Horreum
      include Familia::Features::Autoloader

      SCHEMA = 'models/domain-signin-config'

      # Valid values for restrict_to — matches AuthConfig::RESTRICT_TO_VALUES
      RESTRICT_TO_VALUES = %w[password email_auth webauthn sso].freeze

      # Result of `restrict_to` resolution (ADR-024 A2).
      #
      # Three EXPLICIT states, because the three gates that consume it need to
      # tell them apart and a bare string cannot:
      #
      #   :unrestricted — every globally-enabled sign-in method is offered.
      #                   `restrict_to` is nil. Runtime gate: allow all.
      #   :restricted   — exactly one method is offered. `restrict_to` names
      #                   it. Runtime gate: allow only that method.
      #   :unavailable  — a restriction is in force but its backing method
      #                   cannot be honored here, so NO method is offered
      #                   (ADR-024 A3 fail-closed). `restrict_to` still carries
      #                   the named method so a caller can render a
      #                   method-specific notice. Runtime gate: allow nothing.
      #
      # `source` records which layer decided so the settings API (A4) can
      # explain the effective value without re-deriving it:
      #
      #   :global   — the install-level restriction (or its absence) stands.
      #   :domain   — the per-domain config produced the outcome.
      #   :conflict — global and domain each name a DIFFERENT method, which
      #               intersects to nothing (ADR-024 A8). Always paired with
      #               :unavailable; neither layer won.
      #
      # Use `allows?(method)` for the runtime gate (A1) rather than comparing
      # `restrict_to` — it is the only form that reads correctly in all three
      # states.
      #
      # NOTE: the member is `restrict_to`, not `method`; a `method` member
      # would shadow Object#method on every instance.
      RestrictToResolution = Data.define(:state, :restrict_to, :source) do
        def self.unrestricted(source)
          new(state: :unrestricted, restrict_to: nil, source: source)
        end

        def self.restricted(restrict_to, source)
          new(state: :restricted, restrict_to: restrict_to, source: source)
        end

        def self.unavailable(restrict_to, source)
          new(state: :unavailable, restrict_to: restrict_to, source: source)
        end

        def unrestricted? = state == :unrestricted
        def restricted?   = state == :restricted
        def unavailable?  = state == :unavailable

        # Whether `name` is a sign-in method this resolution permits.
        #
        # This does NOT consider whether the method is enabled globally —
        # restriction is a narrowing filter applied on top of the global
        # capability, so callers still AND it with their own enablement check.
        #
        # @param name [String, Symbol]
        # @return [Boolean]
        def allows?(name)
          return true if unrestricted?
          return false if unavailable?

          restrict_to == name.to_s
        end
      end

      prefix :custom_domain__signin_config

      # domain_id is the CustomDomain's identifier (objid), used as our key.
      # This creates a 1:1 relationship: one signin config per domain.
      identifier_field :domain_id
      field :domain_id

      # Master switch: whether this per-domain signin config is active.
      # Non-nullable boolean, defaults to false.
      field :enabled

      # Non-nullable boolean overrides with conservative defaults (false).
      field :signin_enabled       # Override for AUTH_SIGNIN
      field :restrict_to          # Override for full.restrict_to (string or nil)
      field :email_auth_enabled   # Override for AUTH_EMAIL_AUTH_ENABLED
      # TENANT-SSO activation gate — NOT an override for the platform
      # AUTH_SSO_ENABLED, despite what this comment said until 2026-07.
      # Authority for `sso_permitted_for?` below, which feeds
      # SsoConfig.tenant_sso_available_for? and the omniauth_tenant hook, i.e.
      # whether THIS domain's own SsoConfig credentials may be used to sign in.
      # Reading it as the platform flag is what led the domain sign-in settings
      # UI to gate on (and seed from) the wrong switch.
      field :sso_enabled

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      # Colonel-writable fields, aggregated into
      # {Onetime::CustomDomain::ConfigRegistry::FIELD_SPECS}. This constant is
      # the ONLY place that names this model's colonel-writable fields AND
      # their storage encoding — the registry validates at load time that
      # every key has a setter here, so adding/renaming a field is a one-file
      # change. All boolean fields on this model store REAL booleans
      # (storage :native); the enum references the model constant so values
      # cannot drift.
      FIELD_SPECS = {
        'enabled' => { type: :boolean, storage: :native },
        'signin_enabled' => { type: :boolean, storage: :native },
        'email_auth_enabled' => { type: :boolean, storage: :native },
        'sso_enabled' => { type: :boolean, storage: :native },
        'restrict_to' => { type: :enum, values: RESTRICT_TO_VALUES, nullable: true },
      }.freeze

      # Tolerant predicates + normalizing setters for the boolean fields in
      # FIELD_SPECS above (#3951). Must come after both the field
      # declarations and the constant.
      feature :boolean_encoding

      def init
        self.enabled            = false if enabled.nil?
        self.signin_enabled     = false if signin_enabled.nil?
        self.email_auth_enabled = false if email_auth_enabled.nil?
        self.sso_enabled        = false if sso_enabled.nil?
      end

      # Validate that all required fields are present.
      #
      # @return [Array<String>] List of validation error messages
      def validation_errors
        errors = []

        errors << 'domain_id is required' if domain_id.to_s.empty?

        # restrict_to must be a known value when present
        if restrict_to && !RESTRICT_TO_VALUES.include?(restrict_to)
          errors << "restrict_to must be one of: #{RESTRICT_TO_VALUES.join(', ')}"
        end

        errors
      end

      # Check if the configuration is valid.
      #
      # @return [Boolean] true if no validation errors
      def valid?
        validation_errors.empty?
      end

      # Load the associated CustomDomain record.
      #
      # @return [CustomDomain, nil] The domain or nil if not found
      def custom_domain
        Onetime::CustomDomain.find_by_identifier(domain_id)
      rescue Onetime::RecordNotFound
        nil
      end

      # Load the owning Organization via the CustomDomain.
      #
      # @return [Organization, nil] The organization or nil if not found
      def organization
        domain = custom_domain
        return nil unless domain

        Onetime::Organization.load(domain.org_id)
      end

      class << self
        # Find signin config by domain ID.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::SigninConfig, nil] The config or nil if not found
        def find_by_domain_id(domain_id)
          return nil if domain_id.to_s.empty?

          load(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end

        # Whether the domain's SigninConfig permits SSO as an auth method.
        #
        # Shared permission predicate so the display gate (config serializer)
        # and the runtime gate (omniauth_tenant hook) cannot diverge — both
        # reach it through SsoConfig.tenant_sso_available_for?, so the SSO
        # button is never shown when the auth route would reject, and never
        # hidden when the route works.
        #
        # Master switch off / no config => permitted (defer to SsoConfig
        # credentials). Master switch on => sso_enabled? is authoritative.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [Boolean] true if SSO is permitted for the domain
        def sso_permitted_for?(domain_id)
          config = find_by_domain_id(domain_id)
          return true unless config&.enabled?

          config.sso_enabled?
        end

        # Resolve effective sign-in availability, combining the install-level
        # (global) capability with an optional per-domain override.
        #
        # AND semantics: an enabled per-domain config can only *narrow* the
        # global capability — it can never re-enable sign-in when the operator
        # has disabled it globally (AUTH_ENABLED / AUTH_SIGNIN). When no config
        # is enabled, the global value is authoritative.
        #
        # This is the single source of truth shared by the display gate
        # (Core::Views::ConfigSerializer#resolve_signin) and the
        # runtime gate (Core::Controllers::Base#signin_enabled?), so the
        # rendered page and the POST handler cannot disagree about whether a
        # global kill switch is in effect.
        #
        # @param global [Boolean] install-level availability (auth.enabled && auth.signin)
        # @param config [SigninConfig, nil] the per-domain config, if any
        # @return [Boolean]
        def resolve_signin_enabled(global, config)
          global = global == true
          return global unless config&.enabled?

          global && config.signin_enabled?
        end

        # Effective sign-in availability for a CUSTOM DOMAIN request.
        #
        # Custom domains default OFF: sign-in is available only when the domain
        # owner has explicitly opted in via an *enabled* SigninConfig. Unlike
        # resolve_signin_enabled — which lets an unconfigured CANONICAL request
        # follow the global default (ADR-024 invariant #2) — here both "no
        # config" and "config present but master switch off" mean "not
        # explicitly allowed" and resolve to false. The global kill switch
        # still gates the result: an enabled config can only narrow, never
        # re-enable sign-in disabled globally.
        #
        # Single source of truth for the custom-domain default, shared by the
        # runtime route gate (Core::Controllers::Base#signin_enabled?), the
        # branded-masthead display gate
        # (Core::Views::DomainSerializer#effective_signin_enabled?), and the
        # settings API (DomainsAPI signin_config details, #3814), so the
        # /signin POST handler, the masthead link, and the settings page
        # cannot disagree.
        #
        # SSO carve-out (domain_id:): when the caller passes domain_id, the
        # "not explicitly allowed" branch falls back to
        # SsoConfig.tenant_sso_available_for? instead of false. An SSO-only
        # tenant (enabled SsoConfig, no SigninConfig) has a working /signin
        # page via the omniauth routes, so DISPLAY surfaces — the masthead
        # link and the settings page — must report sign-in as available.
        # Callers gating the password/email POST /signin handler omit
        # domain_id and keep the strict false: SSO never flows through POST
        # /signin, so that asymmetry is intentional (#3415, #3783). An
        # *enabled* config always falls through to the shared resolver, which
        # honors an explicit signin_enabled=false and hides SSO along with it.
        #
        # The carve-out ignores the password-signin `global` param — AUTH_SIGNIN
        # does not govern SSO — but it is NOT exempt from the master switch:
        # tenant_sso_available_for? consults global_auth_enabled (AUTH_ENABLED)
        # itself, so a master kill still resolves false here. With the master
        # switch off, sessionauth is never registered and an SSO sign-in could
        # only mint a session the app ignores, so advertising the link would
        # be a dead end (#3901 follow-up).
        #
        # @param global [Boolean] install-level availability (auth.enabled && auth.signin)
        # @param config [SigninConfig, nil] the per-domain config, if any
        # @param domain_id [String, nil] CustomDomain identifier (objid); when
        #   present, enables the tenant-SSO carve-out for display surfaces
        # @return [Boolean]
        def resolve_signin_enabled_for_custom_domain(global, config, domain_id: nil)
          unless config&.enabled?
            return false if domain_id.nil?

            return Onetime::CustomDomain::SsoConfig.tenant_sso_available_for?(domain_id)
          end

          resolve_signin_enabled(global, config)
        end

        # Resolve effective email-auth (magic-link) availability, combining the
        # install-level capability with an optional per-domain override.
        #
        # Same AND semantics and strict-boolean coercion as resolve_signin_enabled:
        # a domain config can only narrow email-auth, never re-enable it when it
        # is disabled globally. Currently consulted only by the display gate
        # (Core::Views::ConfigSerializer#resolve_email_auth) — there is no runtime
        # email-auth gate today — but routed through here so any future gate uses
        # the same single source of truth and cannot drift.
        #
        # @param global [Boolean] install-level availability (auth_config.email_auth_enabled?)
        # @param config [SigninConfig, nil] the per-domain config, if any
        # @return [Boolean]
        def resolve_email_auth_enabled(global, config)
          global = global == true
          return global unless config&.enabled?

          global && config.email_auth_enabled?
        end

        # Resolve the effective single-sign-in-method restriction, combining
        # the install-level (global) restriction with an optional per-domain
        # override. ADR-024 A2 (invariant 5): this is the ONE owner of
        # restrict_to resolution, consumed by the display gate
        # (Core::Views::ConfigSerializer#resolve_restrict_to), the runtime gate
        # (Core::Controllers::Base, A1) and the settings API `details`
        # (A4). No caller re-derives any part of it.
        #
        # PRECEDENCE — INTERSECTION (ADR-024 A8). A domain config can only
        # narrow, never widen (invariant 1). A record with the master switch
        # off, or no record at all, contributes nothing and global stands
        # (invariant 2).
        #
        #   global | domain      | result
        #   -------|-------------|------------------------------------------
        #   unset  | unset       | :unrestricted            (source :global)
        #   set    | unset       | global method            (source :global)
        #   unset  | set         | domain method            (source :domain)
        #   set    | set, equal  | that method              (source :domain)
        #   set    | set, differ | :unavailable             (source :conflict)
        #
        # The set/unset row is the fix: replace semantics let an enabled
        # domain config with restrict_to UNSET erase an operator's global
        # restriction on that host — a tenant escaping an operator-level
        # control, silently.
        #
        # Two different single-method restrictions have no intersection, so a
        # conflict fails closed instead of picking a winner: picking the
        # domain re-creates the escape above, picking the global silently
        # discards a setting the tenant deliberately made. The :unavailable
        # resolution retains the GLOBAL method name — the operator's
        # restriction is the one still in force — so a notice can say which
        # method this host is held to while `allows?` permits nothing.
        #
        # DOMAIN-HALF DEGRADATION IS FAIL-CLOSED (ADR-024 A3). A domain
        # restriction naming a method that cannot be honored on a custom domain
        # resolves to :unavailable — sign-in offers nothing — never to
        # :unrestricted. Widening would re-expose exactly the methods the
        # domain owner chose to hide. Two cases:
        #
        #   - 'webauthn': passkey credentials are host-scoped (rp_id =
        #     request.host), so a credential registered on the canonical host
        #     can never assert on a custom domain. Not policy, a
        #     not-yet-supported guard — #4137 adds per-domain credential
        #     scoping and retires it (ADR-024 A5). PUT already rejects new
        #     webauthn restrictions; this covers values persisted earlier.
        #   - anything outside RESTRICT_TO_VALUES: invalid data, fails closed
        #     like the rest rather than silently reading as "unrestricted".
        #
        # GLOBAL HALF. `global` is taken at face value as a VALUE: post-#4140,
        # AuthConfig#restrict_to returns a valid restriction or nil meaning "no
        # restriction configured", and never nil to mean "the configured
        # restriction could not be honored" (that is a fatal boot error now).
        # Re-adding defensive nil-handling here would rebuild the silent
        # fail-open A3 retired.
        #
        # GLOBAL AVAILABILITY (`available:`) is the post-boot half of A3. It is
        # not derivable from `global` and `config` — it reads live prerequisite
        # state (AuthConfig#restrict_to_available?) — so the caller supplies it,
        # but this resolver APPLIES it: three consumers each remembering to
        # apply the same rule by hand is precisely the drift A2 exists to
        # eliminate.
        #
        #   available: false means "the global restriction stands, but its
        #   backing method is dead here". It can only ever NARROW: a standing
        #   restriction becomes :unavailable, never :unrestricted, and an
        #   install with nothing restricted (`global` blank) is untouched — a
        #   false flag must not take an unrestricted install dark.
        #
        # The flag describes the VALUE the caller passed as `global`, not
        # whatever AuthConfig happens to hold. That distinction is load-bearing
        # for the display/gate SSO pin, which hands in a HOST property rather
        # than the operator's config; callers derive the flag through
        # .global_restriction_available? so they cannot disagree about it.
        #
        # @param global [String, nil] install-level restriction (AuthConfig#restrict_to),
        #   or nil when nothing is restricted
        # @param config [SigninConfig, nil] the per-domain config, if any
        # @param available [Boolean] whether `global`'s backing method is usable
        #   right now (see .global_restriction_available?)
        # @return [RestrictToResolution] explicit :unrestricted / :restricted / :unavailable
        def resolve_restrict_to(global, config, available: true)
          global_value = global.to_s.strip
          domain_value = config&.enabled? ? config.restrict_to.to_s.strip : ''

          # A blank global has nothing to be unavailable, so the flag cannot
          # reach the :unrestricted row of the table above.
          global_dead = !global_value.empty? && available != true

          if domain_value.empty?
            return RestrictToResolution.unrestricted(:global) if global_value.empty?
            return RestrictToResolution.unavailable(global_value, :global) if global_dead

            return RestrictToResolution.restricted(global_value, :global)
          end

          # A conflict is :unavailable either way; report the richer source.
          unless global_value.empty? || global_value == domain_value
            return RestrictToResolution.unavailable(global_value, :conflict)
          end

          # An AGREEING domain config does not resurrect a dead global method
          # (A8: agreement resolves with source :domain, but the method named is
          # the same one, and it is just as dead). Source stays :global — the
          # global half is why nothing is offered.
          return RestrictToResolution.unavailable(global_value, :global) if global_dead

          resolve_domain_restrict_to(domain_value)
        end

        # The `available:` input to resolve_restrict_to for a caller that has
        # already chosen the `global` VALUE it is handing in.
        #
        # Keyed on the value, not on the caller: AuthConfig#restrict_to_available?
        # describes the OPERATOR's configured restriction, so it applies only
        # when the caller is passing that same restriction through. The display
        # and runtime gates also hand in a derived 'sso' HOST pin
        # (ConfigSerializer#effective_global_restrict_to,
        # Auth::RestrictTo.global_restrict_to) whose availability their own pin
        # predicate already established; AuthConfig has no opinion about it and
        # must not be consulted for it.
        #
        # Defined here, beside global_signin_enabled / global_auth_enabled, so
        # the three resolver consumers read it identically (ADR-024 A2).
        #
        # @param global_value [String, nil] the value being passed as `global`
        # @return [Boolean]
        def global_restriction_available?(global_value)
          return true unless global_value.to_s == Onetime.auth_config.restrict_to.to_s

          Onetime.auth_config.restrict_to_available?
        end

        # Domain half of resolve_restrict_to: a non-empty domain restriction
        # that the global half has already agreed with (or declined to
        # contradict). See its PRECEDENCE and DOMAIN-HALF DEGRADATION notes;
        # do not call this directly.
        #
        # @param value [String] a non-empty persisted domain restrict_to value
        # @return [RestrictToResolution]
        def resolve_domain_restrict_to(value)
          return RestrictToResolution.unavailable(value, :domain) unless honorable_domain_restriction?(value)

          RestrictToResolution.restricted(value, :domain)
        end

        # Whether a persisted domain restriction can be honored on a custom
        # domain at all. False => the restriction stands but resolves to
        # :unavailable (ADR-024 A3).
        #
        # @param value [String] a non-empty persisted restrict_to value
        # @return [Boolean]
        def honorable_domain_restriction?(value)
          return false unless RESTRICT_TO_VALUES.include?(value)

          value != 'webauthn'
        end

        # Install-level sign-in capability — the `global` input to
        # resolve_signin_enabled, defined once so the runtime gate
        # (Core::Controllers::Base#signin_enabled?) and the settings API
        # (DomainsAPI signin_config details) cannot drift in how they read it
        # (ADR-024). Strict-boolean like the resolver: anything but true is
        # treated as off.
        #
        # @param auth [Hash, nil] site.authentication settings (injectable for tests)
        # @return [Boolean]
        def global_signin_enabled(auth = nil)
          auth ||= OT.conf.dig('site', 'authentication') || {}
          (auth['enabled'] && auth['signin']) == true
        end

        # Install-level MASTER authentication switch (AUTH_ENABLED) on its
        # own, without the sign-in flag. This is the gate for sign-in paths
        # that are not password/email — tenant SSO — where AUTH_SIGNIN is
        # deliberately not consulted. The two flags fail differently:
        # AUTH_SIGNIN=false retires only the password/email path while
        # sessions keep working, but AUTH_ENABLED=false means sessionauth is
        # never registered (Application::AuthStrategies.account_creation_allowed?)
        # and every session reads as unauthenticated
        # (SessionHelpers#session_auth_enforced?) — ANY sign-in flow, SSO
        # included, can only mint a session the app then ignores. Consulted
        # by SsoConfig.tenant_sso_available_for? so all tenant-SSO surfaces
        # (masthead link, /signin page, settings API, omniauth runtime hook)
        # go dark together under a master kill. Strict-boolean like the
        # other global readers.
        #
        # @param auth [Hash, nil] site.authentication settings (injectable for tests)
        # @return [Boolean]
        def global_auth_enabled(auth = nil)
          auth ||= OT.conf.dig('site', 'authentication') || {}
          auth['enabled'] == true
        end

        # Check if a domain has signin config.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if signin config exists
        def exists_for_domain?(domain_id)
          return false if domain_id.to_s.empty?

          exists?(domain_id)
        end

        # Create a new signin config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param attrs [Hash] Configuration attributes
        # @return [CustomDomain::SigninConfig] The created config
        # @raise [Onetime::Problem] if config already exists
        def create!(domain_id:, **attrs)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
          raise Onetime::Problem, 'Signin config already exists for this domain' if exists_for_domain?(domain_id)

          config = new(domain_id: domain_id)

          config.enabled            = attrs.key?(:enabled) ? attrs[:enabled] : false
          config.restrict_to        = attrs[:restrict_to] if attrs.key?(:restrict_to)

          # Convention: all boolean fields use conservative defaults (false).
          # The `enabled` master switch gates runtime consultation — creating
          # a record never changes behavior until explicitly enabled.
          config.signin_enabled     = attrs.key?(:signin_enabled) ? attrs[:signin_enabled] : false
          config.email_auth_enabled = attrs.key?(:email_auth_enabled) ? attrs[:email_auth_enabled] : false
          config.sso_enabled        = attrs.key?(:sso_enabled) ? attrs[:sso_enabled] : false

          # Initialize timestamps
          now            = Familia.now.to_i
          config.created = now
          config.updated = now

          config.save

          config
        end

        # Delete signin config for a domain.
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

        # List all domain signin configs.
        #
        # @return [Array<CustomDomain::SigninConfig>] All configs (newest first)
        def all
          identifiers = instances.revrangeraw(0, -1)
          return [] if identifiers.empty?

          load_multi(identifiers).compact
        end

        # Count of domains with signin config.
        #
        # @return [Integer] Number of signin configs
        def count
          instances.size
        end
      end
    end
  end
end
