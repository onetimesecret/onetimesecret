# lib/onetime/tenant_sso_resolution.rb
#
# frozen_string_literal: true

module Onetime
  # The request's tenant SSO answer, resolved once and shared (#4173).
  #
  # Three surfaces ask the same question during a single HTML request —
  # "does this display_domain have tenant SSO, and which record is it?":
  #
  #   1. Core::Views::ConfigSerializer     — renders the SSO button
  #   2. Core::Views::AuthenticationSerializer — enforce_sso_only for the
  #      password affordance
  #   3. Onetime::Middleware::TenantCspExtras  — widens CSP form-action with
  #      that record's IdP origin so the button's POST can actually leave
  #
  # They each used to walk the ladder themselves (domain index → SsoConfig →
  # tenant_sso_available_for?), which cost 3+ round trips per render and,
  # worse, let the surfaces disagree: an operator disabling an SsoConfig
  # mid-request could have the page render the button while the middleware
  # skipped the widening (or the reverse), reproducing the exact #4173
  # symptom — a silently blocked redirect with no server-side error. One
  # resolution per request makes divergence impossible by construction.
  #
  # Lifecycle: lazy and request-scoped. Construction reads nothing; the
  # datastore is touched on the first #domain_id / #sso_config call and the
  # answer (including nil and the failure sentinel) is memoized for the rest
  # of the request. The instance lives in the rack env under ENV_KEY, so the
  # serializers (inside the app, reached via view_vars) and the middleware
  # (outside it, on the way OUT) share one object. No lock: a rack env
  # belongs to exactly one request on one thread.
  #
  # Read semantics deliberately follow the DISPLAY half (#4157): the domain
  # lookup is CustomDomain.load_by_display_domain — which normalizes case
  # internally, and returns nil for a dangling index entry whose record will
  # not hydrate — and a datastore error answers DOMAIN_READ_FAILED rather
  # than nil, so callers can render the narrowest surface instead of reading
  # a blip as "no tenant config". Callers that only care about SSO treat the
  # sentinel like nil (#sso_config already does).
  class TenantSsoResolution
    # Where the shared instance lives on the rack env, and in the view_vars
    # hash that Core::Views::InitializeViewVars derives from that env.
    ENV_KEY      = 'onetime.tenant_sso_resolution'
    VIEW_VAR_KEY = 'tenant_sso_resolution'

    # Returned by #domain_id when the datastore read fails — NOT nil, which
    # means "no such custom domain". Same sentinel value the ConfigSerializer
    # constant of the same name carries (#4157).
    DOMAIN_READ_FAILED = :domain_read_failed

    # The request's resolution, creating and installing it on first ask.
    #
    # @param env [Hash] rack env, after DetectHost published display_domain
    # @return [TenantSsoResolution]
    def self.for(env)
      return new(nil) unless env.is_a?(Hash)

      env[ENV_KEY] ||= new(env['onetime.display_domain'])
    end

    # The resolution carried by view_vars, or a fresh unshared one.
    #
    # The fallback keeps every caller working when view_vars was built
    # without a rack env (specs, tryouts, error-recovery renders): the
    # answers are identical, only the sharing is lost.
    #
    # @param view_vars [Hash]
    # @return [TenantSsoResolution]
    def self.from_view_vars(view_vars)
      carried = view_vars[VIEW_VAR_KEY]
      return carried if carried.is_a?(self)

      new(view_vars['display_domain'])
    end

    attr_reader :display_domain

    def initialize(display_domain)
      @display_domain = display_domain.to_s
    end

    # @return [String, nil, :domain_read_failed] CustomDomain objid, nil when
    #   the host is blank or not a registered custom domain, or the sentinel
    #   when the datastore read failed.
    def domain_id
      return @domain_id if defined?(@domain_id)

      @domain_id = read_domain_id
    end

    # @return [Boolean] true when the domain read failed (#4157 tri-state)
    def domain_read_failed?
      domain_id == DOMAIN_READ_FAILED
    end

    # The tenant's SsoConfig when tenant SSO is AVAILABLE for this request,
    # nil otherwise.
    #
    # Single-read contract: the record is loaded once and handed to
    # SsoConfig.tenant_sso_available_for? through its sso_config:
    # pass-through, so the verdict and the returned record are the same
    # object. Checking first and re-loading after would leave a window where
    # an operator disabling the config between the two reads passes the check
    # but returns nil.
    #
    # @return [Onetime::CustomDomain::SsoConfig, nil]
    def sso_config
      return @sso_config if defined?(@sso_config)

      @sso_config = read_sso_config
    end

    # @return [Boolean] true when tenant SSO is available for this request
    def available?
      !sso_config.nil?
    end

    private

    def read_domain_id
      return nil if @display_domain.empty?

      Onetime::CustomDomain.load_by_display_domain(@display_domain)&.identifier
    rescue Redis::BaseError => ex
      OT.le '[TenantSsoResolution] datastore error resolving domain_id for ' \
            "domain=#{@display_domain}: #{ex.class}"
      DOMAIN_READ_FAILED
    end

    def read_sso_config
      identifier = domain_id
      return nil if identifier.nil? || identifier == DOMAIN_READ_FAILED

      config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(identifier)
      return nil if config.nil?
      return nil unless Onetime::CustomDomain::SsoConfig.tenant_sso_available_for?(
        identifier, sso_config: config
      )

      config
    end
  end
end
