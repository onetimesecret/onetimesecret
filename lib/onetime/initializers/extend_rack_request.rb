# lib/onetime/initializers/extend_rack_request.rb
#
# frozen_string_literal: true

# Extend Rack::Request with Otto and Onetime-specific methods
#
# This provides a clean, consistent interface for accessing authentication
# state, session, locale, and other request-scoped data across controllers,
# views, and Rhales templates.
#
# All methods delegate to env keys set by Otto middleware.

class Rack::Request
  # =========================================================================
  # AUTHENTICATION (Otto StrategyResult)
  # =========================================================================

  # Get Otto's StrategyResult (canonical authentication state)
  #
  # @return [Otto::Security::Authentication::StrategyResult, nil]
  # @note Returns nil in contexts without Otto middleware (e.g., rake tasks, console)
  def strategy_result
    env['otto.strategy_result']
  end

  # Get authenticated user object
  #
  # @return [Object, nil] User object or nil for anonymous/non-middleware requests
  def user
    strategy_result&.user
  end

  # Get Rack session via StrategyResult
  #
  # Using strategy_result.session ensures we get the same session object
  # that Otto's authentication strategies use.
  #
  # @return [Hash] Rack session hash
  def session
    strategy_result&.session || env['rack.session'] || {}
  end

  # Check if request is authenticated
  #
  # @return [Boolean] true if authenticated, false otherwise
  def authenticated?
    strategy_result&.authenticated? || false
  end

  # Get authentication method used for this request
  #
  # @return [String, nil] Auth method or nil if not authenticated
  def auth_method
    strategy_result&.auth_method
  end

  # =========================================================================
  # ONETIME-SPECIFIC
  # =========================================================================

  # Get current customer (Onetime-specific user object)
  #
  # Never returns nil - returns Customer.anonymous for unauthenticated requests.
  #
  # @return [Onetime::Customer] Customer object (authenticated or anonymous)
  def current_customer
    user.is_a?(Onetime::Customer) ? user : Onetime::Customer.anonymous
  end

  # Get current organization from strategy result metadata
  #
  # @return [Onetime::Organization, nil] Current organization or nil
  def organization
    return @organization if defined?(@organization)

    result = strategy_result
    return nil unless result

    context = result.metadata[:organization_context]
    @organization = context[:organization] if context
  end

  # Get current organization ID
  #
  # @return [String, nil] Organization objid or nil
  def organization_id
    organization&.objid
  end

  # Get current team from strategy result metadata
  #
  # @return [Onetime::Team, nil] Current team or nil
  def team
    return @team if defined?(@team)

    result = strategy_result
    return nil unless result

    context = result.metadata[:organization_context]
    @team = context[:team] if context
  end

  # Get current team ID
  #
  # @return [String, nil] Team objid or nil
  def team_id
    team&.objid
  end

  # Switch to a different organization
  #
  # Updates session and clears cache. Organization change takes effect
  # on the next request.
  #
  # @param org_id [String] Organization objid to switch to
  # @return [Boolean] true if switch was successful
  def switch_organization(org_id)
    return false unless user && org_id
    return false unless env['rack.session']

    org = Onetime::Organization.load(org_id)
    return false unless org && org.member?(user)

    session['organization_id'] = org_id

    # Clear cache to force reload on next request
    cache_key = "org_context:#{user.objid}"
    session.delete(cache_key)

    # Update current request's memoized value
    @organization = org

    true
  rescue StandardError => ex
    OT.le "[Rack::Request#switch_organization] Failed to switch: #{ex.message}"
    false
  end

  # Switch to a different team within current organization
  #
  # @param team_id [String] Team objid to switch to
  # @return [Boolean] true if switch was successful
  def switch_team(team_id)
    return false unless user && team_id && organization
    return false unless env['rack.session']

    team = Onetime::Team.load(team_id)
    return false unless team
    return false unless team.organization_id == organization.objid
    return false unless team.member?(user)

    session['team_id'] = team_id

    # Clear cache to force reload on next request
    cache_key = "org_context:#{user.objid}"
    session.delete(cache_key)

    # Update current request's memoized value
    @team = team

    true
  rescue StandardError => ex
    OT.le "[Rack::Request#switch_team] Failed to switch: #{ex.message}"
    false
  end

  # =========================================================================
  # LOCALE (Otto Locale Detection)
  # =========================================================================

  # Get resolved locale for this request
  #
  # @return [String] Locale code (e.g., 'en', 'es', 'fr')
  def locale
    env['otto.locale'] || OT.default_locale
  end

  # =========================================================================
  # SECURITY (CSP Nonce)
  # =========================================================================

  # Get CSP nonce for this request
  #
  # Generated by Onetime's RequestSetup middleware.
  #
  # @return [String, nil] Base64-encoded nonce or nil if not in middleware context
  def nonce
    env['onetime.nonce']
  end

  # =========================================================================
  # PRIVACY (IP Masking)
  # =========================================================================

  # Get masked IP address (privacy-safe)
  #
  # @return [String, nil] Masked IP or nil if privacy disabled
  def masked_ip
    env['otto.privacy.masked_ip']
  end

  # Get geo-location country code
  #
  # @return [String, nil] ISO 3166-1 alpha-2 country code or nil
  def geo_country
    env['otto.privacy.geo_country']
  end

  # Get hashed IP (for session correlation)
  #
  # @return [String, nil] Hexadecimal hash string or nil
  def hashed_ip
    env['otto.privacy.hashed_ip']
  end

  # =========================================================================
  # HTTP HEADERS (Convenience Methods)
  # =========================================================================

  # Check if request accepts specific content type
  #
  # @param content_type [String] Content type to check (e.g., 'application/json')
  # @return [Boolean] true if Accept header includes content type
  def accepts?(content_type)
    accept_header = env['HTTP_ACCEPT']
    return false unless accept_header

    accept_header.split(',').any? do |type|
      type.strip.split(';').first == content_type
    end
  end

  # Check if request is AJAX
  #
  # Delegates to Rack's built-in xhr? method
  # @return [Boolean] true if X-Requested-With: XMLHttpRequest
  def ajax?
    xhr?
  end
end
