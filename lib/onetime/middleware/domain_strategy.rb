# lib/onetime/middleware/domain_strategy.rb
#
# frozen_string_literal: true

require 'public_suffix'
require_relative '../logger_methods'

module Onetime
  module Middleware
    # DomainStrategy Middleware
    #
    # Classifies incoming request domains and determines the appropriate routing strategy.
    #
    # Instantiated once per Rack application in the modular monolith. Multiple instances
    # share class-level configuration while maintaining isolated request processing.
    #
    # @example Domain Classification
    #   example.com        #=> :canonical (configured primary domain)
    #   www.example.com    #=> :canonical (www variant of primary)
    #   api.example.com    #=> :subdomain (subdomain of primary)
    #   partner.com        #=> :custom (partner domain from database)
    #   invalid.tld        #=> :invalid (malformed or unrecognized)
    #
    # @note Adds to Rack environment:
    #   - env['onetime.display_domain']  : Normalized domain for display
    #   - env['onetime.domain_strategy'] : Classification symbol (:canonical, :subdomain, :custom, :invalid)
    #
    # ## :invalid is NOT only a property of the hostname (#4139)
    #
    # The one-liner above reads as if :invalid described the host. It also
    # describes a FAILURE. There are two ways to land on it, and downstream
    # code that treats them alike is wrong for one of them:
    #
    # 1. The host is genuinely unplaceable — unparseable by PublicSuffix, or
    #    matching nothing in the canonical set and no CustomDomain record.
    #    Not a customer domain, so operator treatment is correct.
    # 2. `known_custom_domain?` RAISED. That predicate is a datastore read
    #    (`CustomDomain.from_display_domain`); `Chooserator.choose_strategy`
    #    wraps the whole chain in `rescue StandardError => ex … nil`, and
    #    `call` turns that nil into :invalid (`resolved_domain_strategy =
    #    domain_strategy || :invalid`). So a datastore blip classifies a REAL
    #    customer domain :invalid, and every consumer testing `== :custom`
    #    silently downgrades it to the operator's own polarity.
    #
    # Case 2 is why a fail-closed check must be a POSITIVE test against
    # :canonical/:subdomain and never `!= :custom` — see
    # Onetime::CustomDomain::SigninConfig.operator_host?.
    #
    # ## Invariant: a datastore failure can never PRODUCE :canonical/:subdomain
    #
    # The property that makes those two safe to carve out of a fail-closed
    # rule is one-directional, and it is worth stating precisely because the
    # obvious stronger version is FALSE:
    #
    # - :canonical is fully read-free. The exact / `www.` arm runs BEFORE
    #   `known_custom_domain?`, so the canonical host classifies :canonical
    #   whether or not the datastore is reachable.
    # - :subdomain is NOT read-free. Its sweeps run AFTER
    #   `known_custom_domain?`, and the rescue wraps the entire if/elsif
    #   chain — so a raise aborts the method rather than falling through, and
    #   a subdomain host classifies :invalid during a blip. It fails closed
    #   with the custom domains; it does not quietly keep operator treatment.
    #
    # Neither can be MANUFACTURED by a failure, which is the direction the
    # carve-out depends on: `operator_host?` may only ever be over-strict
    # during an outage, never over-permissive. Preserve that. A new datastore
    # read added to `choose_strategy` ahead of the exact canonical arm would
    # break it silently and take canonical sign-in dark with everything else.
    #
    # ## How downstream reads this
    #
    # Consumers split into two groups, and the split IS the policy
    # (ADR-024#identity-predicates-are-not-auth-gates):
    #
    # - AUTH decisions ask a POSITIVE test — `SigninConfig.operator_host?`,
    #   true for :canonical/:subdomain only. Everything else fails closed with
    #   the custom domains, including nil.
    # - IDENTITY / presentation decisions test `== :custom`, so :invalid and
    #   nil take the operator/generic branch. That is correct for branding and
    #   routing: a genuinely unplaceable host has no tenant.
    #
    # `call` always sets the env key, so nil reaches a consumer only outside a
    # served request (internal callers, code invoked off the Rack path). Both
    # groups already answer it correctly: fail-closed for auth, generic for
    # presentation. One exception to know about — the view layer substitutes its
    # own `:default` sentinel when the key is absent
    # (InitializeViewVars: `req.env.fetch('onetime.domain_strategy', :default)`),
    # which is not a classification this middleware can produce; it is neither
    # :custom nor an operator host, so it lands on the same safe branches.
    #
    # This table is pinned by
    # spec/unit/domain_strategy_classification_contract_spec.rb — a new
    # consumer that disagrees with it fails there, not in review.
    #
    #   Consumer                                         :invalid resolves to
    #   ------------------------------------------------ --------------------
    #   -- positive operator_host? test (auth) --
    #   SigninConfig.operator_host?                       FAIL CLOSED (503)
    #     (via resolve_lookup_failure; read-failure path only)
    #   SigninConfig.resolve_signin_enabled_for_request   tenant-safe (OFF)
    #   SignupConfig.resolve_signup_enabled_for_request   tenant-safe (OFF)
    #   Base#signin_enabled? (via the request resolver)   tenant-safe (OFF)
    #   Base#signup_enabled? (via the request resolver)   tenant-safe (OFF)
    #   ConfigSerializer#operator_domain?                 false
    #   ConfigSerializer#resolve_signin (via that helper) tenant-safe (OFF,
    #                                                     SSO carve-out only)
    #   -- `== :custom` identity test (branding, routing, narrowing) --
    #   Core::Controllers::Base#custom_domain_request?    false
    #   Auth::RestrictTo `custom_host:`                   false (no narrowing)
    #   Auth::RestrictTo host pin                         no 'sso' pin
    #   ConfigSerializer#tenant_domain?                   false
    #   DomainSerializer                                  no branding applied
    #   InitializeViewVars / GetFavicon                   default favicon
    #   API v1 Logic::Base#custom_domain?                 false
    #
    # The auth rows used to read "operator polarity": they chose their branch
    # on `== :custom`, so a case-2 :invalid INVERTED the default — custom
    # domains are default-OFF for sign-in and sign-up while canonical follows
    # the operator's global setting. They now require positive evidence, and
    # the display gate (ConfigSerializer) moves with the runtime gates so the
    # /signin page cannot advertise what the POST will reject. The identity
    # predicates were deliberately left alone.
    # ADR-024#identity-predicates-are-not-auth-gates
    class DomainStrategy
      include Onetime::LoggerMethods

      @canonical_domain         = nil
      @domains_enabled          = nil
      @canonical_domains        = nil
      @canonical_domains_parsed = nil
      @anchor_domains_parsed    = nil
      @link_domains             = nil

      # Domain Context Override state (set at boot from config/env)
      @domain_context_enabled  = nil
      @domain_context_override = nil

      unless defined?(MAX_SUBDOMAIN_DEPTH)
        MAX_SUBDOMAIN_DEPTH = 10 # e.g., a.b.c.d.e.f.g.h.i.j.example.com
        MAX_TOTAL_LENGTH    = 253 # RFC 1034 section 3.1

        # Domain Context Override constants
        DOMAIN_CONTEXT_HEADER  = 'HTTP_O_DOMAIN_CONTEXT'
        DOMAIN_CONTEXT_ENV_VAR = 'DOMAIN_CONTEXT'
      end

      # Initializes the DomainStrategy middleware instance.
      #
      # Each Rack application in the monolith gets its own DomainStrategy instance.
      # Multiple instances share CLASS-LEVEL state for efficiency (see ClassMethods below).
      #
      # ## Instance vs. Class State
      #
      # Instance-level state (per app):
      #   - @app: The next Rack application in the middleware chain
      #   - @application_context: Metadata about which app this middleware serves
      #
      # Class-level state (shared by all instances):
      #   - @canonical_domain: The primary display host (default || site.host)
      #   - @domains_enabled: Whether custom domain feature is active
      #   - @canonical_domains / @canonical_domains_parsed: Full canonical set
      #     (site.host, features.domains.default AND features.domains.link_domains)
      #     used for classification
      #   - @anchor_domains_parsed: The ANCHOR subset of the parsed canonical
      #     set (site.host + features.domains.default only, never a link-pool
      #     member). Only the anchors get the peer/parent/subdomain sweeps —
      #     see Chooserator#choose_strategy.
      #   - @link_domains: The resolved link-picker pool (#4063). A SUBSET of the
      #     canonical set, and a different question: the canonical set is what we
      #     will SERVE, the pool is what we OFFER. An internal canonical host can
      #     serve while being absent from the pool.
      #
      # The initialize call to `initialize_from_config()` is idempotent across instances.
      # Subsequent calls overwrite class variables, but this is safe because configuration
      # is static at boot time and identical for all instances.
      #
      # @param app [Object] The Rack application to wrap
      # @param application_context [Hash] Optional context about the application
      #   (e.g., { name: 'Core::Application', prefix: '/' })
      def initialize(app, application_context: nil)
        @app                 = app
        @application_context = application_context

        domains_config      = OT.conf&.dig('features', 'domains') || {}
        self.class.initialize_from_config(domains_config)

        boot_logger.debug 'DomainStrategy initialized',
          {
            app_context: @application_context,
            canonical_domain: canonical_domain,
          }
      end

      # Processes the incoming request and classifies the domain.
      #
      # This method is called for EVERY REQUEST routed to this middleware instance.
      # In a modular monolith with multiple apps, different instances handle different
      # URL prefixes, but all share the same domain classification logic via class state.
      #
      # ## Request Flow
      #
      # 1. Reads detected host from env (set by Rack::DetectHost middleware)
      # 2. Uses class-level state (@canonical_domain) to classify the domain
      # 3. Stores classification results in env (request-specific)
      # 4. Passes env to next middleware via @app.call(env)
      #
      # ## Rack Environment Variables
      #
      # - env['onetime.display_domain']: Normalized domain for rendering/logging
      # - env['onetime.domain_strategy']: Classification (:canonical, :subdomain, :custom, :invalid)
      #
      # @param env [Hash] The Rack environment hash
      # @return [Array] Standard Rack response array [status, headers, body]
      def call(env)
        display_domain  = canonical_domain
        domain_strategy = :canonical

        if domains_enabled?
          # Check for domain context override first (development feature)
          override_domain, override_source = detect_domain_override(env)
          if override_domain
            display_domain  = override_domain
            domain_strategy = :custom

            http_logger.info '[DomainStrategy] override active',
              {
                domain: override_domain,
                source: override_source,
                strategy: domain_strategy,
              }
          else
            display_domain  = env[Rack::DetectHost.result_field_name]
            # OT.ld "[middleware] DomainStrategy: detected_host=#{display_domain.inspect} result_field_name=#{Rack::DetectHost.result_field_name}"
            domain_strategy = Chooserator.choose_strategy(
              display_domain,
              canonical_domains_parsed,
              anchor_domains: anchor_domains_parsed,
            )
          end
        end

        resolved_domain_strategy = domain_strategy || :invalid # make sure never nil

        # Sanitize display_domain for use in response headers (defense in depth).
        # Both code paths (DetectHost result and override header) should produce
        # valid hostnames, but we guard here to prevent header injection.
        unless Onetime::Utils::DomainParser.basically_valid?(display_domain)
          display_domain = canonical_domain
        end

        env['onetime.display_domain']  = display_domain
        env['onetime.domain_strategy'] = resolved_domain_strategy

        http_logger.debug '[DomainStrategy] determined',
          {
            host: display_domain,
            strategy: resolved_domain_strategy,
          }

        status, headers, body        = @app.call(env)
        headers['O-Domain-Strategy'] = resolved_domain_strategy.to_s
        headers['O-Display-Domain']  = display_domain.to_s
        [status, headers, body]
      end

      # Detects domain context override from environment or request header.
      #
      # Override priority (first match wins):
      # 1. DOMAIN_CONTEXT env var (set at process startup)
      # 2. O-Domain-Context request header (per-request override)
      #
      # @param env [Hash] The Rack environment hash
      # @return [Array<String, Symbol>, Array<nil, nil>] [domain, source] or [nil, nil]
      def detect_domain_override(env)
        detected_host = env[Rack::DetectHost.result_field_name]

        http_logger.debug '[DomainStrategy] detect_domain_override check',
          {
            domain_context_enabled: domain_context_enabled?,
            detected_host: detected_host,
            env_var: ENV.fetch(DOMAIN_CONTEXT_ENV_VAR, nil),
            header: env[DOMAIN_CONTEXT_HEADER],
          }

        return unless domain_context_enabled?

        # Check env var first (process-level override)
        env_override = ENV.fetch(DOMAIN_CONTEXT_ENV_VAR, nil)
        return [env_override, :env_var] unless env_override.to_s.empty?

        # Check request header (per-request override)
        header_override = env[DOMAIN_CONTEXT_HEADER]
        return [header_override, :header] unless header_override.to_s.empty?

        # Implicit override: browser navigated to a host outside the canonical
        # set. A request to site.host is NOT an implicit override even when
        # features.domains.default names a different host.
        return [detected_host, :detected_host] if detected_host && !canonical_host?(detected_host)

        [nil, nil]
      end

      # True when host matches one of the configured canonical hosts
      # (features.domains.default, site.host, or a features.domains.link_domains
      # member), normalized comparison.
      def canonical_host?(host)
        self.class.canonical_host?(host)
      end

      def domain_context_enabled?
        self.class.domain_context_enabled
      end

      def canonical_domain
        self.class.canonical_domain # string or nil if not configured
      end

      # Resolved link-picker pool (#4063): the hosts offered in the
      # domain-context dropdown. Always at least [canonical_domain].
      def link_domains
        self.class.link_domains || []
      end

      def domains_enabled?
        Onetime::Runtime.features.domains?
      end

      # Full canonical set for classification. Empty when domains are
      # disabled or the configured hosts could not be parsed.
      def canonical_domains_parsed
        self.class.canonical_domains_parsed || []
      end

      # The anchor subset of the parsed canonical set: site.host and
      # features.domains.default only. This is what the peer/parent and
      # subdomain sweeps iterate — a link-pool member participates by exact
      # match only (#4063). See Chooserator#choose_strategy.
      def anchor_domains_parsed
        self.class.anchor_domains_parsed || []
      end

      module Chooserator
        class << self
          # Determines the domain strategy for a request domain.
          #
          # Accepts one or more canonical hosts. In a split deployment,
          # site.host and features.domains.default are BOTH canonical anchors:
          # an exact match against ANY host is :canonical.
          #
          # Precedence (#3841): an exact canonical-set match always wins,
          # then a REGISTERED custom domain, then the subdomain/peer sweeps
          # across the ANCHOR hosts. The registration lookup must run before the
          # sweeps: a registered custom domain under a canonical host's base
          # domain (e.g. secrets.acme.io when site.host=acme.io) must keep
          # :custom — per-domain brand/signin config is gated on that
          # classification — while an exact canonical match still beats a
          # (misconfigured) identical registration.
          #
          # ## Exact-match set vs. sweep set (#4063)
          #
          # `canonical_domains` is the EXACT-match set: every canonical host,
          # including features.domains.link_domains members. Matched with
          # `exact_host?` (name equality), NOT `equal_to?` — the latter also
          # accepts the `www.` variant of a host's registrable domain, which
          # over a pool member silently widens the grant to a host the
          # operator never blessed. With link_domains=['go.acme.com'], an
          # `equal_to?` match here classified `www.acme.com` :canonical ahead
          # of the known_custom_domain? lookup below, dropping that tenant's
          # brand/signin config. The www tolerance is retained, scoped to the
          # ANCHORS, by the second half of the same arm.
          #
          # `anchor_domains` is the set the www-variant tolerance and the
          # peer/parent and subdomain SWEEPS iterate, and it is deliberately
          # narrower — the two ANCHOR hosts (site.host,
          # features.domains.default). It defaults to `canonical_domains`,
          # which is the pre-#4063 identity for any caller that has no pool
          # (the two sets are then equal).
          #
          # DO NOT "fix" the sweeps back onto the full set for consistency.
          # An operator blesses one specific link host, not its base domain.
          # With link_domains=['go.acme.com'], sweeping the full set makes an
          # UNREGISTERED other.acme.com classify :canonical via peer_of? —
          # a wide grant on a shared public suffix, and a reintroduction of
          # the Shlink-style host passthrough #4063 explicitly declines.
          # CustomDomain.overlaps_canonical_domain? draws the same line (its
          # base-domain arm is anchor-only, its exact arm covers the pool);
          # these two must keep agreeing.
          #
          # @param request_domain [String] The domain from the current request
          # @param canonical_domains [PublicSuffix::Domain, String, Array] The
          #   configured canonical host(s), pool members included
          # @param anchor_domains [PublicSuffix::Domain, String, Array, nil]
          #   The anchor subset to sweep; nil means "same as canonical_domains"
          # @return [Symbol, nil] Domain strategy (:canonical, :subdomain, :custom) or nil if invalid
          def choose_strategy(request_domain, canonical_domains, anchor_domains: nil)
            canonical_domains = [canonical_domains] unless canonical_domains.is_a?(Array)
            canonical_domains = canonical_domains.compact
            # Guard against empty canonical set (can happen if class init ran before Runtime.features was set)
            return nil if canonical_domains.empty?
            return nil if request_domain.nil? || request_domain.to_s.strip.empty?

            canonical_domains = parse_host_set(canonical_domains)
            return nil if canonical_domains.empty?

            # An empty anchor set means no sweeps at all, never a fallback to
            # the full set: with no anchors there is nothing whose base domain
            # the deployment owns.
            sweep_domains = anchor_domains.nil? ? canonical_domains : parse_host_set(anchor_domains)

            request_domain = Parser.parse(request_domain)

            # Exact match against the FULL canonical set (pool included), plus
            # the `www.` variant tolerance against the ANCHORS only. Splitting
            # the arm this way keeps the pre-#4063 behavior identical whenever
            # the two sets are equal, while a pool member participates by exact
            # match alone.
            if canonical_domains.any? { |host| exact_host?(request_domain, host) } ||
               sweep_domains.any? { |host| equal_to?(request_domain, host) }
              :canonical
            elsif known_custom_domain?(request_domain.name)
              :custom
            elsif sweep_domains.any? { |host| canonical?(request_domain, host) } # rubocop:disable Lint/DuplicateBranch
              :canonical
            elsif sweep_domains.any? { |host| subdomain_of?(request_domain, host) }
              :subdomain
            end
          rescue PublicSuffix::DomainInvalid => ex
            Onetime.http_logger.debug 'Invalid domain in strategy selection',
              {
                exception: ex,
                request_domain: host_label(request_domain),
              }
            nil
          rescue StandardError => ex
            # Names, not objects: a PublicSuffix::Domain inspects to its ivars
            # and reads as noise in the log line.
            Onetime.http_logger.error 'Unhandled error in domain strategy',
              {
                exception: ex,
                request_domain: host_label(request_domain),
                canonical_domains: canonical_domains.map { |host| host_label(host) },
              }
            nil
          end

          # @param host [PublicSuffix::Domain, String, nil]
          # @return [String, nil] the bare host name for a log line
          def host_label(host)
            return nil if host.nil?

            host.respond_to?(:name) ? host.name : host.to_s
          end

          # Parses a host set per-element, skipping unparseable hosts (e.g. an
          # IP literal site.host in dev) so one bad entry cannot poison the
          # whole set — mirrors ClassMethods#parse_canonical_set. Elements that
          # are already parsed pass through untouched, which is the normal case
          # for the middleware (both sets arrive pre-parsed from class state).
          #
          # @param hosts [PublicSuffix::Domain, String, Array]
          # @return [Array<PublicSuffix::Domain>]
          def parse_host_set(hosts)
            hosts = [hosts] unless hosts.is_a?(Array)
            hosts.compact.filter_map do |host|
              host.is_a?(PublicSuffix::Domain) ? host : Parser.parse(host)
            rescue PublicSuffix::DomainInvalid => ex
              Onetime.http_logger.debug 'Skipping unparseable canonical host in strategy selection',
                {
                  host: host,
                  error: ex.message,
                }
              nil
            end
          end

          # Checks if domain matches canonical domain or its standard variants.
          #
          # @param d [PublicSuffix::Domain] Domain to check
          # @param canonical_domain [PublicSuffix::Domain] Canonical domain
          # @return [Boolean] true if domain is canonical or a canonical variant
          def canonical?(d, canonical_domain)
            (
              equal_to?(d, canonical_domain) ||
              peer_of?(d, canonical_domain) ||
              parent_of?(d, canonical_domain)
            )
          end

          # Strict host equality: the same name, nothing else. This is the ONLY
          # predicate safe to run over the full canonical set, because that set
          # includes features.domains.link_domains members (#4063) and an
          # operator blesses one specific link host — never a sibling of it.
          #
          # @param left [PublicSuffix::Domain]
          # @param right [PublicSuffix::Domain]
          # @return [Boolean]
          def exact_host?(left, right)
            return false unless left.domain? && right.domain?

            left.name.eql?(right.name)
          end
          # exact_host?('example.com', 'example.com')     # => true
          # exact_host?('www.example.com', 'example.com') # => false (see equal_to?)

          # Host equality WITH the `www.` variant tolerance. Only ever applied
          # to ANCHOR hosts: over a pool member the second arm matches any
          # `www.<registrable-domain>` sibling, which is a grant the operator
          # did not make.
          def equal_to?(left, right)
            return false unless left.domain? && right.domain?

            left.name.eql?(right.name) || (left.domain.eql?(right.domain) && left.trd.eql?('www'))
          end
          # equal_to?('Example.com', 'example.com') # => true
          # equal_to?('sub.EXAMPLE.COM', 'sub.example.com') # => true
          # equal_to?('example.com', 'different.com') # => false
          # equal_to?('', 'example.com') # => false
          # equal_to?(nil, 'example.com') # => false

          def peer_of?(left, right)
            return false unless left.subdomain? && right.subdomain?

            # NOTE: We do not re-check if the domains are the same
            left.domain.eql?(right.domain)
          end
          # peer_of?('blog.example.com', 'shop.example.com') # => true
          # peer_of?('sub.blog.example.com', 'sub.shop.example.com') # => true
          # peer_of?('blog.example.com', 'example.com') # => false
          # peer_of?('blog.example.com', 'blog.other.com') # => false
          # peer_of?('example.com', 'example.com') # => false

          def parent_of?(left, right)
            return false unless !left.subdomain? && right.subdomain?

            left.name.eql?(right.domain)
          end
          # subdomain_of?('sub.example.com', 'example.com') # => true
          # subdomain_of?('other.com', 'example.com') # => false
          # subdomain_of?('deep.sub.example.com', 'example.com') # => true
          # subdomain_of?('eu.onetimesecret.com', 'onetimesecret.com') # => false
          # subdomain_of?('.onetimesecret.com', 'eu.onetimesecret.com') # => false

          def subdomain_of?(left, right)
            return false unless left.subdomain? && !right.subdomain?

            left.domain.eql?(right.name)
          end
          # subdomain_of?('sub.example.com', 'example.com') # => true
          # subdomain_of?('other.com', 'example.com') # => false
          # subdomain_of?('deep.sub.example.com', 'example.com') # => true
          # subdomain_of?('example.com', 'example.com') # => false

          # Checks if domain is registered as a custom domain in the database.
          #
          # @param potential_custom_domain [String] Domain to check
          # @return [Boolean] true if domain exists in CustomDomain table
          def known_custom_domain?(potential_custom_domain)
            # This will load the model if it hasn't been loaded yet
            # and avoid circular references between lib and v2.
            !Onetime::CustomDomain.from_display_domain(potential_custom_domain).nil?
          end
        end
      end

      # Domain parsing utilities with validation.
      #
      # Delegates to Onetime::Utils::DomainParser for hostname extraction and
      # validation to maintain a single source of truth for domain parsing logic.
      module Parser
        class << self
          # Parses and validates a host string into a domain object.
          #
          # @param host [String] The host to parse (port will be stripped)
          # @return [PublicSuffix::Domain] Parsed domain object
          # @raise [PublicSuffix::DomainInvalid] When domain is invalid or malformed
          def parse(host)
            # Delegate hostname extraction (port stripping, normalization) to DomainParser
            host = Onetime::Utils::DomainParser.extract_hostname(host)
            raise PublicSuffix::DomainInvalid.new('Cannot parse host') unless basically_valid?(host)

            PublicSuffix.parse(host, default_rule: nil, ignore_private: false) # calls normalize
          end

          # Performs basic validation checks before parsing.
          #
          # @param input [String] The input string to validate
          # @return [Boolean] true if input passes basic validation
          #
          # Delegates to Onetime::Utils::DomainParser.basically_valid? for
          # consistent validation logic across the codebase.
          def basically_valid?(input)
            Onetime::Utils::DomainParser.basically_valid?(input)
          end
        end
      end

      # Shared Configuration State
      #
      # This module extends the DomainStrategy class to provide shared configuration
      # across all middleware instances.
      #
      # ## Why Class-Level State?
      #
      # DomainStrategy instances are created multiple times (once per Rack app), but
      # the configuration (canonical domain, feature flags) is the same for all instances.
      # Class variables avoid redundant parsing and initialization.
      #
      #
      # @note If dynamic reconfiguration is needed, consider using a thread-safe
      #   configuration store (e.g., monitor pattern) instead of class variables.
      module ClassMethods
        attr_reader :canonical_domain,
          :domains_enabled,
          :canonical_domains,
          :canonical_domains_parsed,
          :anchor_domains_parsed,
          :link_domains,
          :domain_context_enabled

        alias domains_enabled? domains_enabled
        alias domain_context_enabled? domain_context_enabled

        # Sets class instance variables based on the site configuration.
        def initialize_from_config(domains_config)
          raise ArgumentError, 'Configuration cannot be nil' if domains_config.nil?

          Onetime.http_logger.debug 'DomainStrategy initializing from config',
            {
              domains_enabled_before: domains_enabled,
            }

          @domains_enabled = domains_config.fetch('enabled', false)

          default_host = domains_enabled ? domains_config['default'] : nil
          site_host    = OT.conf.dig('site', 'host') || nil
          # Gated exactly like default_host. CanonicalHosts.link_hosts:
          # DEFAULTS to reading features.domains.link_domains, so this call
          # site MUST pass the kwarg explicitly — omitting it would let the
          # link pool join the canonical set even with domains disabled.
          link_hosts   = domains_enabled ? domains_config['link_domains'] : nil

          # Canonical SET, derived through Utils::CanonicalHosts (the single
          # derivation point shared with CustomDomain). Primary host first:
          # features.domains.default when the feature is enabled, else
          # site.host. In a split deployment (site.host serves the app,
          # default anchors generated links) a request to either host must
          # classify :canonical, never :invalid.
          #
          # #4063: features.domains.link_domains joins the set too, appended
          # after both anchors so the primary is unchanged. That membership is
          # what makes an operator link domain hit the exact-match arm in
          # Chooserator (:canonical) rather than falling through to nil
          # (:invalid). It does NOT make it a link anchor — see
          # CanonicalHosts.anchor_hosts.
          @canonical_domains        = Onetime::Utils::CanonicalHosts.hosts(
            default_host: default_host, site_host: site_host, link_hosts: link_hosts,
          )
          @canonical_domain         = @canonical_domains.first
          @canonical_domains_parsed = []
          @anchor_domains_parsed    = []
          # Provisional pool: correct for the domains-disabled and
          # unparseable-primary paths, both of which return/raise before the
          # parsed set exists. Recomputed from the parsed set below.
          @link_domains             = [@canonical_domain].compact

          # Load domain context override setting from development config
          dev_config              = OT.conf&.dig('development') || {}
          @domain_context_enabled = dev_config['domain_context_enabled'] == true

          Onetime.http_logger.debug 'DomainStrategy config loaded',
            {
              domains_enabled: domains_enabled,
              canonical_domain: canonical_domain,
              canonical_domains: canonical_domains,
              link_domains: link_domains,
              domain_context_enabled: domain_context_enabled,
            }

          # We don't need to get into any domain parsing if domains are disabled
          return unless domains_enabled?

          # The primary host must parse: failure lands in the DomainInvalid
          # rescue below, which disables the domains feature.
          Parser.parse(canonical_domain)
          @canonical_domains_parsed = parse_canonical_set(canonical_domains)
          @anchor_domains_parsed    = select_anchor_domains(default_host: default_host, site_host: site_host)
          @link_domains             = resolve_link_domains(link_hosts)
        rescue PublicSuffix::DomainInvalid => ex
          OT.le "[middleware] DomainStrategy: Invalid canonical domain: #{canonical_domain.inspect} error=#{ex.message}"
          @domains_enabled = false
        end

        # Set-backed membership test for the canonical host set, normalized
        # on both sides (case, port). Public API for callers outside the
        # middleware (auth hooks, logic classes) so they agree with request
        # classification about which hosts are canonical.
        #
        # Answers against the PARSED set whenever it is populated, because
        # that is the set `Chooserator#choose_strategy` classifies against.
        # Reading the raw @canonical_domains strings instead used to let an
        # unparseable entry (a typo'd features.domains.link_domains member,
        # now an everyday occurrence) pass admission in
        # Account::UpdateDomainContext and then classify :invalid on the very
        # next request — an accepted context the middleware rejects.
        #
        # The raw set remains the fallback for the pre-parse / domains-disabled
        # window, where the parsed set is legitimately empty.
        #
        # @param host [String, nil] Host to test (port/case-insensitive)
        # @return [Boolean] true when host is one of the canonical hosts
        def canonical_host?(host)
          normalized = Onetime::Utils::DomainParser.extract_hostname(host)
          return false if normalized.nil?

          parsed = canonical_domains_parsed
          unless parsed.nil? || parsed.empty?
            return parsed.any? { |candidate| Onetime::Utils::DomainParser.extract_hostname(candidate.name) == normalized }
          end

          hosts = canonical_domains
          hosts = [canonical_domain].compact if hosts.nil? || hosts.empty?
          hosts.any? { |candidate| Onetime::Utils::DomainParser.extract_hostname(candidate) == normalized }
        end

        # Parses each canonical host, skipping unparseable entries (e.g. an IP
        # literal site.host in dev). The primary host is parsed separately and
        # still disables domains on failure.
        #
        # A skip is a per-host config defect, never a feature-level one: the
        # remaining hosts keep serving and domains_enabled? stays true. Logged
        # at error level (naming the host) because reaching here means the
        # PRIMARY parsed while a sibling did not, which is always operator
        # error rather than the tolerated dev IP-literal case.
        def parse_canonical_set(hosts)
          hosts.filter_map do |host|
            Parser.parse(host)
          rescue PublicSuffix::DomainInvalid => ex
            OT.le "[middleware] DomainStrategy: skipping unparseable canonical host: #{host.inspect} " \
                  "error=#{ex.message} (remaining canonical hosts unaffected)"
            nil
          end
        end

        # Selects the ANCHOR subset out of the already-parsed canonical set:
        # site.host and features.domains.default, never a
        # features.domains.link_domains member (#4063).
        #
        # This is the set `Chooserator#choose_strategy` runs its peer/parent
        # and subdomain sweeps over. A pool member participates in
        # classification by EXACT match only: the operator blessed one host,
        # not everything sharing its base domain, which on a shared public
        # suffix would be a very wide grant. `canonical_host?` (exact) and
        # `CustomDomain.overlaps_canonical_domain?` (exact arm over the full
        # set, base-domain arm over anchors only) draw the same line.
        #
        # Selecting from @canonical_domains_parsed rather than re-parsing
        # keeps this free of a second round of parse failures — and of a
        # second "skipping unparseable canonical host" log line for the same
        # host, which the boot-log assertions in
        # try/integration/middleware/domain_strategy/multiple_canonical_try.rb
        # would see. Anchors are a subset of the canonical set by
        # construction, so nothing can be missed here.
        #
        # @return [Array<PublicSuffix::Domain>] possibly empty (both anchors
        #   unparseable or unset), which correctly disables the sweeps
        def select_anchor_domains(default_host:, site_host:)
          anchors = Onetime::Utils::CanonicalHosts.normalized_anchor_hosts(
            default_host: default_host, site_host: site_host,
          )
          return [] if anchors.empty?

          Array(canonical_domains_parsed).select do |parsed|
            anchors.include?(Onetime::Utils::DomainParser.extract_hostname(parsed.name))
          end
        end

        # Resolves the link-picker pool (#4063) from the PARSED canonical set,
        # ordered by the configured pool.
        #
        # Deriving from the parsed set is what keeps the pool and
        # classification in agreement: a pool entry we could not parse is not
        # served as :canonical, so it must not be offered either.
        #
        # Entries come back NORMALIZED (lowercased, port-stripped) because they
        # are taken from the parsed set, so the picker can compare them
        # directly against CustomDomain display_domain values.
        #
        # An UNSET pool (link_hosts nil) resolves to [canonical_domain] — the
        # pre-#4063 behavior, and the only case that may fall back. A pool the
        # operator DID configure never falls back to the canonical host: doing
        # so re-exposes the internal platform address in the picker, which is
        # the precise outcome LINK_DOMAINS exists to prevent. A configured pool
        # where nothing resolves is operator error, and
        # Onetime::Config.validate_link_domains! already fails boot on it — the
        # empty return here only covers callers that drive
        # initialize_from_config directly (specs, console) and so never passed
        # through that gate.
        #
        # @param link_hosts [Array<String>, nil] features.domains.link_domains,
        #   already gated on domains_enabled by the caller
        # @return [Array<String>] [canonical_domain] when unset; otherwise the
        #   resolved subset of the configured pool, possibly empty
        def resolve_link_domains(link_hosts)
          return [canonical_domain].compact if link_hosts.nil?

          parsed_names = Array(canonical_domains_parsed).map(&:name)
          configured   = Onetime::Utils::CanonicalHosts.link_pool(link_hosts: link_hosts)

          resolved = configured.filter_map do |host|
            normalized = Onetime::Utils::DomainParser.extract_hostname(host)
            parsed_names.find { |name| name == normalized }
          end
          resolved.uniq!

          if resolved.empty?
            OT.le '[middleware] DomainStrategy: features.domains.link_domains ' \
                  "#{configured.inspect} named no parseable host; the link picker pool is empty. " \
                  'Fix LINK_DOMAINS or unset it to offer the canonical domain.'
          end

          resolved
        end

        # Whether a host is a member of the resolved operator link pool
        # (#4063), and therefore admissible as a share_domain.
        #
        # Single authority for that question, so the secret-creation logic
        # (apps/api/v{1,2}/logic/secrets/base_secret_action.rb#link_pool_host?)
        # can never admit a host the middleware would classify :invalid.
        # Reading features.domains.link_domains out of config directly is what
        # let that drift happen: it skipped BOTH gates applied here — the
        # features.domains.enabled check, and membership in the PARSED
        # canonical set — so with domains disabled, or with a typo'd entry,
        # guests could anchor secrets on hosts the middleware never serves as
        # canonical and the picker never offers.
        #
        # @param host [String, nil] Host to test (port/case-insensitive)
        # @return [Boolean]
        def link_pool_host?(host)
          return false unless domains_enabled?

          pool = link_domains
          return false if pool.nil? || pool.empty?

          normalized = Onetime::Utils::DomainParser.extract_hostname(host)
          return false if normalized.nil?

          pool.any? { |candidate| Onetime::Utils::DomainParser.extract_hostname(candidate) == normalized }
        end

        def reset!
          @canonical_domain         = nil
          @domains_enabled          = nil
          @canonical_domains        = nil
          @canonical_domains_parsed = nil
          @anchor_domains_parsed    = nil
          @link_domains             = nil
          @domain_context_enabled   = nil
        end
      end

      extend ClassMethods
    end
  end
end
