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
#      docs/adr/adr-024-custom-domain-auth-override-resolution.md
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

      # DomainStrategy classifications for the operator's OWN surfaces, the
      # only hosts no per-domain config can speak for. Used by
      # resolve_lookup_failure to decide who survives an unreadable policy;
      # :custom, :invalid and nil all fail closed there.
      #
      # Safe to carve out because these two are decided from in-memory config
      # alone — a datastore failure can neither produce nor withdraw them. The
      # invariant, the two ways a request reaches :invalid, and the full table
      # of what every other consumer does with it live at the producer:
      # Onetime::Middleware::DomainStrategy's class doc. Do not restate it
      # here; it will drift.
      OPERATOR_HOST_STRATEGIES = [:canonical, :subdomain].freeze

      # Result of `restrict_to` resolution (ADR-034#resolution-is-model-owned).
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
      #                   (ADR-034#degradation-is-fail-closed). `restrict_to`
      #                   still carries the named method so a caller can
      #                   render a method-specific notice. Runtime gate:
      #                   allow nothing.
      #
      # `source` records which layer decided so the settings API
      # (ADR-034#settings-api-serializes-effective-restrict-to) can explain
      # the effective value without re-deriving it:
      #
      #   :global   — the install-level restriction (or its absence) stands.
      #   :domain   — the per-domain config produced the outcome.
      #   :conflict — global and domain each name a DIFFERENT method, which
      #               intersects to nothing
      #               (ADR-034#resolution-intersects-never-widens). Always
      #               paired with :unavailable; neither layer won.
      #
      # Use `allows?(method)` for the runtime gate
      # (ADR-034#restrict-to-is-an-access-control-not-a-display-preference)
      # rather than comparing
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

        # Wire form of the resolution — the ONE serialization every API app
        # emits (settings API `details.effective_restrict_to`,
        # ADR-034#settings-api-serializes-effective-restrict-to;
        # `GET /api/invite/:token` record.effective_restrict_to,
        # ADR-034#invite-signup-is-gated), so a single client-side type
        # describes both. The Data object owns its own serialization: two API
        # apps each carrying a private copy of this hash is the drift shape
        # ADR-034#resolution-is-model-owned exists to kill, one level down.
        #
        # The three states survive serialization intact. In particular
        # :unavailable is NOT projected down to a bare null the way the display
        # field `features.restrict_to` must be (string-or-null cannot express
        # it), so a consumer can say "SSO required, and it is not available
        # here" instead of rendering an unrestricted-looking blank.
        #
        # NOT `to_h`: Data#to_h emits the members verbatim, i.e. Symbol values
        # for state and source. The wire contract is strings (JSON has no
        # symbol, and the specs/tryouts pin string values pre-serialization).
        # Overriding to_h to stringify would make the Data object lie about its
        # own members to every other reader, so this is a separate method.
        #
        # @return [Hash] state ('unrestricted'|'restricted'|'unavailable'),
        #   restrict_to (String or nil),
        #   source ('domain'|'global'|'conflict')
        def to_wire
          {
            state: state.to_s,
            restrict_to: restrict_to,
            source: source.to_s,
          }
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

        # Effective sign-in availability for a REQUEST, chosen by the request's
        # DomainStrategy classification (ADR-024 A12).
        #
        # OPERATOR DEFAULTS REQUIRE POSITIVE EVIDENCE. The two context-free
        # resolvers above have OPPOSITE defaults — resolve_signin_enabled
        # follows the operator's global setting, resolve_signin_enabled_for_custom_domain
        # is default-OFF — so choosing between them IS the access-policy
        # decision. Choosing on `== :custom` picks the operator branch for
        # :invalid and nil as well, and :invalid is what DomainStrategy answers
        # when its own datastore read RAISES for a REAL customer domain. A blip
        # would then hand that domain the operator's global default, i.e. an
        # availability failure widening authentication access on a domain whose
        # owner never opted in.
        #
        # So this asks operator_host?, a POSITIVE test: only :canonical and
        # :subdomain — the two classifications a datastore failure can never
        # manufacture — inherit operator defaults. :custom, :invalid and nil all
        # take the tenant-safe branch. The cost is fail-closed, not fail-open: a
        # recognized subdomain can be held to the stricter default during an
        # outage (the subdomain sweep runs after the datastore read, so it is
        # withdrawn too), which denies nothing that was ever explicitly granted.
        #
        # The domain identity predicates are deliberately NOT redefined to match
        # (Core::Controllers::Base#custom_domain_request?,
        # ConfigSerializer.tenant_domain?): those also decide branding, routing
        # and tenant presentation, which a genuinely unknown host must not
        # receive. The fix belongs here, at policy resolution, not there.
        #
        # @param global [Boolean] install-level availability (auth.enabled && auth.signin)
        # @param config [SigninConfig, nil] the per-domain config, if any
        # @param domain_strategy [Symbol, String, nil] env['onetime.domain_strategy']
        # @param domain_id [String, nil] CustomDomain identifier; pass it on
        #   DISPLAY surfaces to keep the tenant-SSO carve-out, omit it on the
        #   password/email POST gate (see resolve_signin_enabled_for_custom_domain)
        # @return [Boolean]
        def resolve_signin_enabled_for_request(global, config, domain_strategy:, domain_id: nil)
          return resolve_signin_enabled(global, config) if operator_host?(domain_strategy)

          resolve_signin_enabled_for_custom_domain(global, config, domain_id: domain_id)
        end

        # Resolve effective email-auth (magic-link) availability, combining the
        # install-level capability with an optional per-domain override.
        #
        # Same AND semantics and strict-boolean coercion as resolve_signin_enabled:
        # a domain config can only narrow email-auth, never re-enable it when it
        # is disabled globally.
        #
        # Two consumers today, and the second is a RUNTIME gate — this comment
        # used to say there was no runtime email-auth gate, which stopped being
        # true when #4139 landed A1 and cost a reviewer a false bug report:
        #
        #   - display: Core::Views::ConfigSerializer#resolve_email_auth
        #   - runtime: restriction_available_for_custom_domain? below, which
        #     decides whether a restrict_to='email_auth' host can honor its own
        #     restriction, and feeds Auth::RestrictTo — so a domain that turned
        #     email-auth off now takes the magic-link ROUTES dark, not just the
        #     button.
        #
        # Which is exactly why resolution was routed through here in the first
        # place: the second consumer arrived without either side drifting.
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
        # override. ADR-034#resolution-is-model-owned (invariant 5): this is
        # the ONE owner of restrict_to resolution, consumed by the display
        # gate (Core::Views::ConfigSerializer#resolve_restrict_to), the
        # runtime gate (Core::Controllers::Base,
        # ADR-034#restrict-to-is-an-access-control-not-a-display-preference)
        # and the settings API `details`
        # (ADR-034#settings-api-serializes-effective-restrict-to). No caller
        # re-derives any part of it.
        #
        # PRECEDENCE — INTERSECTION
        # (ADR-034#resolution-intersects-never-widens). A domain config can only
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
        # DOMAIN-HALF DEGRADATION IS FAIL-CLOSED
        # (ADR-034#degradation-is-fail-closed). A domain
        # restriction naming a method that cannot be honored on a custom domain
        # resolves to :unavailable — sign-in offers nothing — never to
        # :unrestricted. Widening would re-expose exactly the methods the
        # domain owner chose to hide. Two cases:
        #
        #   - 'webauthn': passkey credentials are host-scoped (rp_id =
        #     request.host), so a credential registered on the canonical host
        #     can never assert on a custom domain. Not policy, a
        #     not-yet-supported guard — #4137 adds per-domain credential
        #     scoping and retires it
        #     (ADR-034#custom-domain-webauthn-fails-closed-pending-rp-id-scoping).
        #     PUT already rejects new
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
        # @param domain_available [Boolean, nil] injectable domain-method verdict;
        #   nil derives it from the live custom-host capabilities
        # @return [RestrictToResolution] explicit :unrestricted / :restricted / :unavailable
        def resolve_restrict_to(global, config, available: true, domain_available: nil)
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

          structurally_unavailable = !RESTRICT_TO_VALUES.include?(domain_value) || domain_value == 'webauthn'
          domain_dead              = structurally_unavailable || if domain_available.nil?
                                                       !restriction_available_for_custom_domain?(domain_value, config)
                                                     else
                                                       domain_available != true
                                                     end

          # An AGREEING domain config does not resurrect a dead global method
          # (ADR-034#resolution-intersects-never-widens: agreement resolves
          # with source :domain, but the method named is
          # the same one, and it is just as dead). Source stays :global — the
          # global half is why nothing is offered.
          return RestrictToResolution.unavailable(global_value, :global) if global_dead
          return RestrictToResolution.unavailable(domain_value, :domain) if domain_dead

          RestrictToResolution.restricted(domain_value, :domain)
        end

        # What a gate answers when the policy for this request host could NOT
        # be read (ADR-034#restrict-to-is-an-access-control-not-a-display-preference
        # / #degradation-is-fail-closed, #4139).
        #
        # UNCONDITIONAL FAIL-CLOSED ON A CUSTOM HOST. Half the policy for such
        # a host lives in the datastore — the CustomDomain identity, its
        # SigninConfig, the SSO availability probes — so a read failure means
        # the gate does not know what this host permits. It must not guess in
        # either direction: continuing with the global half alone re-exposes
        # exactly the methods a per-domain restriction hides (the A3 failure
        # mode), and degrading to "unrestricted because nothing is globally
        # restricted" makes the answer depend on a value that says nothing
        # about this host. Sign-in fails, loudly, until the read works.
        #
        # The 503 is what makes that survivable. See
        # Onetime::SigninPolicyUnavailable: the gate's normal reject shape is a
        # 404 that deliberately looks like an undefined route, and wearing it
        # here would manufacture a mystery restriction on an install that has
        # none. An honest, alertable "backend read failed" does not.
        #
        # OPERATOR HOSTS ARE CARVED OUT, and this is not a softening: a
        # canonical or subdomain request has no per-domain half to lose. Its
        # restriction is the operator's global one, which is in-memory config
        # that cannot have failed, so the policy is still fully known and still
        # enforced. Failing those requests would take the canonical sign-in page
        # dark for a read that could only ever have narrowed a host this request
        # is not on.
        #
        # The carve-out is a POSITIVE test against those two classifications,
        # not `!= :custom`. DomainStrategy also answers :invalid (and nil, for
        # a request that never passed through it) for hosts it could not
        # classify — including, when the domain index read is the one that
        # failed, a host that IS a customer's custom domain. Carving out
        # everything that is not :custom would hand those the global-only
        # answer, which is the widen this whole path exists to refuse. The
        # producer-side account of that failure mode is in
        # Onetime::Middleware::DomainStrategy's class doc ("two ways to land
        # on :invalid").
        #
        # The invariant that makes the carve-out safe is one-directional: a
        # datastore failure can never MANUFACTURE :canonical or :subdomain,
        # so this test may only ever be over-strict during an outage. It can
        # withdraw :subdomain, though — those sweeps run after the datastore
        # read, so subdomain hosts fail closed alongside the custom domains
        # while canonical sign-in stays up.
        #
        # @param domain_strategy [Symbol, nil] env['onetime.domain_strategy']
        # @raise [Onetime::SigninPolicyUnavailable] on any host that is not positively an operator host
        # @return [RestrictToResolution] the global-only resolution, on an operator host
        def resolve_lookup_failure(domain_strategy:)
          raise Onetime::SigninPolicyUnavailable unless operator_host?(domain_strategy)

          global = Onetime.auth_config.restrict_to
          resolve_restrict_to(global, nil, available: global_restriction_available?(global))
        end

        # Whether the request host's sign-in policy is entirely in-memory
        # config — i.e. no per-domain override can apply to it, so a datastore
        # failure costs it nothing. See resolve_lookup_failure.
        #
        # @param domain_strategy [Symbol, String, nil] env['onetime.domain_strategy']
        # @return [Boolean]
        def operator_host?(domain_strategy)
          OPERATOR_HOST_STRATEGIES.include?(domain_strategy&.to_sym)
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
        # the three resolver consumers read it identically
        # (ADR-034#resolution-is-model-owned).
        #
        # @param global_value [String, nil] the value being passed as `global`
        # @return [Boolean]
        def global_restriction_available?(global_value)
          return true unless global_value.to_s == Onetime.auth_config.restrict_to.to_s

          Onetime.auth_config.restrict_to_available?
        end

        # The `available:` input to resolve_restrict_to for a REQUEST — the
        # whole post-boot availability question, which is two questions: the
        # operator's own prerequisites (global_restriction_available?) and,
        # on a custom host, whether the method that restriction names can run
        # on THAT host at all.
        #
        # WHY THIS LIVES HERE and not in the gate that first needed it (#4139).
        # It is policy, not request wiring: the only request facts it needs are
        # "is this host a custom domain" and "which domain", both passed in
        # explicitly, so every consumer can ask it — the runtime gate holding a
        # Rack env (Auth::RestrictTo.restriction_available_for_host?), the
        # display serializer holding view_vars
        # (Core::Views::ConfigSerializer#restrict_to_resolution), and the
        # settings API holding a domain record
        # (DomainsAPI::Logic::SigninConfig::Base#signin_override_details).
        #
        # It lived in the gate for one commit and the two display consumers did
        # not follow, which reproduced the very drift
        # ADR-034#resolution-is-model-owned legislates against, one layer
        # down — the resolver was shared, its INPUT was not.
        # The observable symptom: a custom host with no enabled SigninConfig
        # under a global `restrict_to='password'`. The gate narrowed through the
        # custom-host capabilities (password defaults OFF on custom domains),
        # resolved :unavailable and 404'd every Rodauth route, while the
        # serializer still reported `restricted/password` and the page rendered
        # a sign-in form whose routes were dark.
        #
        # NARROWING ONLY. Three explicit pass-throughs, each of which would
        # otherwise take a host dark for no reason:
        #   - a canonical host has no custom-domain capabilities to intersect;
        #   - an install with nothing restricted (`global` blank) has nothing to
        #     be unavailable — a false flag must never manufacture a restriction;
        #   - a custom host we could not classify (domain_id nil) has no domain
        #     whose capabilities could narrow the verdict.
        #
        # @param global [String, nil] the value being handed to resolve_restrict_to as `global`
        # @param config [SigninConfig, nil] the host's per-domain config, if any
        # @param domain_id [String, nil] the classified CustomDomain identifier (objid)
        # @param custom_host [Boolean] whether the request host is a custom domain
        # @return [Boolean]
        def restriction_available_for_request?(global, config, domain_id: nil, custom_host: false)
          available = global_restriction_available?(global)
          return available unless available && custom_host == true

          global_value = global.to_s.strip
          return available if global_value.empty? || domain_id.nil?

          restriction_available_for_custom_domain?(global_value, config, domain_id: domain_id)
        end

        # Whether a restriction's backing method is usable on a custom host.
        # This is shared by domain restrictions and inherited global
        # restrictions: either one must resolve :unavailable when the only
        # method it permits cannot actually run on this host.
        #
        # Password and email-auth use the custom-domain sign-in opt-in as well
        # as their install-wide capability. Email-auth additionally requires
        # both the domain field and the full-mode feature. SSO asks the host
        # availability predicate, which includes tenant credentials and the
        # operator-controlled platform fallback. WebAuthn remains unavailable
        # until credentials are scoped per custom host (#4137).
        #
        # @param value [String] a persisted restrict_to value
        # @param config [SigninConfig, nil] the host's per-domain config
        # @param domain_id [String, nil] the classified custom-domain identifier
        # @return [Boolean]
        def restriction_available_for_custom_domain?(value, config, domain_id: nil)
          return false unless RESTRICT_TO_VALUES.include?(value)

          domain_id ||= config&.domain_id

          case value
          when 'password'
            resolve_signin_enabled_for_custom_domain(global_signin_enabled, config)
          when 'email_auth'
            resolve_signin_enabled_for_custom_domain(global_signin_enabled, config) &&
              resolve_email_auth_enabled(Onetime.auth_config.email_auth_enabled?, config)
          when 'sso'
            # ASK THE AUTHORITY THAT SERVES THE ROUTE. `restrict_to` gates the
            # SSO sign-in ROUTE, so its availability verdict must come from the
            # ladder that route obeys: sso_available_for_tenant_host? →
            # tenant_sso_available_for? → tenant_sso_unavailable_reason →
            # SigninConfig.sso_permitted_for?, which keys on `sso_enabled?`.
            # That ladder is also what apps/web/auth/config/hooks/
            # omniauth_tenant.rb reads, so a host omniauth will happily serve
            # can never be reported :unavailable here. Two authorities
            # disagreeing about one route is precisely what
            # ADR-034#resolution-is-model-owned forbids.
            #
            # `signin_enabled?` is deliberately NOT consulted, and a
            # short-circuit on it lived here briefly (#4139): a config with
            # enabled=true, sso_enabled=true, signin_enabled=false resolved
            # :unavailable and 404'd an SSO route omniauth_tenant served
            # successfully. signin_enabled is the PASSWORD/EMAIL opt-in
            # (resolve_signin_enabled) — the two cases above that consult it do
            # so because their methods are the ones it governs.
            #
            # The display side genuinely reads differently:
            # resolve_signin_enabled_for_custom_domain lets an enabled config's
            # signin_enabled=false hide SSO from the masthead link and the page
            # availability verdict. That display/route asymmetry pre-dates this
            # fix and is left exactly as it was — changing display semantics is
            # not in scope here. What is in scope is that restrict_to, which
            # gates the ROUTE, agrees with the route.
            Onetime::CustomDomain::SsoConfig.sso_available_for_tenant_host?(domain_id)
          else
            false
          end
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
