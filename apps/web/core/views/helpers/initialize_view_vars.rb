# apps/web/core/views/helpers/initialize_view_vars.rb
#
# frozen_string_literal: true

require 'onetime/logger_methods'

module Core
  module Views
    # InitializeViewVars
    #
    # This module is meant to be extended and not included. That's why
    # initialize_view_vars takes the arguments it does instead of relying on
    # instance variables and their attr_reader methods.
    module InitializeViewVars
      extend Onetime::LoggerMethods

      # Define fields that are safe to expose to the frontend
      # Explicitly excluding :secret and :authenticity which contain sensitive data
      @safe_site_fields = %w[
        host ssl interface
        secret_options authentication
        support
      ]

      class << self
        attr_reader :safe_site_fields
      end

      # Initialize core variables used throughout view rendering. These values
      # are the source of truth for te values that they represent. Any other
      # values that the serializers want can be derived from here.
      #
      # @param req [Rack::Request] Current request object
      # @param sess [Hash, nil] Pre-resolved session (optional, extracted from strategy_result if nil)
      # @param cust [Customer, nil] Pre-resolved customer (optional, extracted from strategy_result if nil)
      # @return [Hash] Collection of initialized variables
      def initialize_view_vars(req, sess = nil, cust = nil)
        # Extract the top-level keys from the YAML configuration.
        #
        # SECURITY: This implementation follows an opt-in approach for configuration filtering.
        # We explicitly whitelist fields that are safe to share and filter nested sensitive data.
        # This prevents accidental exposure of sensitive information to the frontend.
        #
        # Sensitive data types being protected:
        # - Secret keys and credentials (:secret, nested :cluster)
        # - Authentication tokens (:authenticity)
        # - Internal infrastructure details
        #
        site_config     = OT.conf.fetch('site', {})
        features_config = OT.conf.fetch('features', {})
        development     = OT.conf.fetch('development', {})
        diagnostics     = OT.conf.fetch('diagnostics', {})

        safe_site     = build_safe_site_config(site_config)
        safe_features = build_safe_features_config(features_config)

        # Extract values from session
        #
        # Use pre-resolved sess/cust if provided (from BaseView#initialize),
        # otherwise extract from strategy_result or fallback values
        if sess.nil? || cust.nil?
          strategy_result = req.env.fetch('otto.strategy_result', nil)

          if strategy_result
            # Normal flow: Otto ran, strategy_result available
            sess        ||= strategy_result.session
            cust        ||= strategy_result.user # nil for anonymous
            authenticated = strategy_result.authenticated? || false
          else
            # Error recovery flow: Otto didn't run, use fallback values
            begin
              sess ||= req.session
            rescue NoMethodError, RuntimeError
              sess = {}
            end
            # cust stays nil for anonymous
            authenticated = false
          end
        else
          # Using pre-resolved values from BaseView#initialize
          strategy_result = req.env.fetch('otto.strategy_result', nil)
          authenticated   = strategy_result&.authenticated? || false
        end

        # Generate masked CSRF token from the canonical Rack session, NOT the
        # strategy-resolved `sess` which may be a detached {} on anonymous
        # routes (NoAuthStrategy). Using rack.session ensures the token is
        # persisted in the same store that Rack::Protection checks on submit.
        # AuthenticityToken.token() handles both generation and per-request
        # masking (mitigates BREACH).
        rack_session = req.env['rack.session']
        shrimp       = if rack_session
                   Rack::Protection::AuthenticityToken.token(rack_session)
                 end

        awaiting_mfa = sess&.[]('awaiting_mfa') || false

        # DEBUG: Log session state
        Onetime.session_logger.debug 'Session',
          {
            account_id: sess&.[]('account_id'),
            external_id: sess&.[]('external_id'),
            module: 'InitializeViewVars',
            awaiting_mfa: awaiting_mfa,
            authenticated: authenticated,
          }

        # When awaiting_mfa is true, user has NOT completed authentication
        # Do NOT load customer from Redis - they don't have access yet
        # The frontend will show minimal MFA prompt using email from session
        session_email = sess&.[]('email')

        # ====================================================================
        # Bridge Rodauth flash messages to Core app messages
        # ====================================================================
        #
        # When Rodauth sets flash messages (e.g., SSO failure), they are stored
        # in session['_flash'] by Roda's flash plugin. We read these and convert
        # them to the Core app's messages format, then clear them (standard flash
        # behavior - messages shown once).
        #
        # Flash keys from Rodauth:
        # - :error - Error messages (e.g., "SSO authentication failed")
        # - :notice - Success/info messages
        #
        messages   = []
        flash_data = sess&.delete('_flash') || sess&.delete(:_flash)
        if flash_data.is_a?(Hash)
          error_msg  = flash_data[:error] || flash_data['error']
          notice_msg = flash_data[:notice] || flash_data['notice']

          messages << { 'type' => 'error', 'content' => error_msg } if error_msg
          messages << { 'type' => 'info', 'content' => notice_msg } if notice_msg
        end

        # Extract values from rack request object
        nonce           = req.env.fetch('onetime.nonce', nil)
        domain_strategy = req.env.fetch('onetime.domain_strategy', :default)
        display_domain  = req.env.fetch('onetime.display_domain', nil)
        locale          = req.env.fetch('otto.locale', OT.default_locale)

        # Normalize locale for I18n - validate against available_locales
        # Otto may detect locales that aren't configured in I18n backend
        # (e.g., from Accept-Language header or URL params)
        i18n_locale = if I18n.available_locales.include?(locale.to_sym)
                        locale.to_sym
                      else
                        I18n.default_locale
                      end

        # Controller-level flag whether to display the "internal use only"
        # message. Possible values are nil, 'protected'.
        homepage_mode = req.env.fetch('onetime.homepage_mode', nil)

        # Extract organization from strategy result metadata
        # This is populated by OrganizationLoader in the auth strategy
        organization = nil
        if strategy_result&.metadata
          org_context  = strategy_result.metadata[:organization_context]
          organization = org_context[:organization] if org_context
        end

        # HTML Tag vars. These are meant for the view templates themselves
        # and not the onetime state window data passed on to the Vue app (
        # although a serializer could still choose to include any of them).
        description          = I18n.t('web.COMMON.description', locale: i18n_locale, default: 'Keep sensitive info out of your chat logs & email')
        keywords             = I18n.t('web.COMMON.keywords', locale: i18n_locale, default: 'secret,password,share,private,link')

        # Brand config — source of truth for tag-level branding (page_title,
        # theme-color, etc.) and for default Vue app theming on first paint.
        brand_config         = OT.conf.fetch('brand', {})
        brand_product_name   = brand_config['product_name'] ||
                               Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS[:product_name]

        # Use the display domain name for branded instances, otherwise the
        # configured brand product name. site_name (the deprecated
        # site.interface.ui.header.branding.site_name) is kept only as a tail
        # fallback for instances mid-migration; remove once consumers update.
        site_name            = site_config.dig('interface', 'ui', 'header', 'branding', 'site_name')
        page_title           = display_domain || brand_product_name || site_name
        no_cache             = false
        frontend_host        = development['frontend_host']
        frontend_development = development['enabled']
        script_element_id    = 'onetime-state'

        # URI helpers for templates
        site_host            = safe_site['host']
        base_scheme          = safe_site['ssl'] == false ? 'http://' : 'https://'
        baseuri              = base_scheme + site_host

        # Brand config exposed to view templates (theme-color, manifest, etc.)
        # and to first-paint Vue state. BrandSettingsConstants supplies the
        # neutral fallbacks (#3B82F6, allow_public_* = false) per #3049.
        brand_defaults              = Onetime::CustomDomain::BrandSettingsConstants::DEFAULTS
        brand_primary_color         = brand_config['primary_color'] ||
                                      brand_defaults[:primary_color]
        support_email               = brand_config['support_email'] ||
                                      Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS[:support_email]
        # docs_host: full documentation URL exposed to bootstrap. Sources from
        # DOCS_URL env var with the same default the YAML footer link uses, since
        # the legacy site.support.host path was retired in #1461.
        docs_host                   = ENV.fetch('DOCS_URL', 'https://docs.onetimesecret.com/')
        brand_corner_style          = brand_config['corner_style'] || brand_defaults[:corner_style]
        brand_font_family           = brand_config['font_family'] || brand_defaults[:font_family]
        brand_button_text_light     = brand_config.fetch('button_text_light', brand_defaults[:button_text_light])
        brand_allow_public_homepage = brand_config.fetch('allow_public_homepage', false)
        brand_allow_public_api      = brand_config.fetch('allow_public_api', false)
        # Site-wide brand fields not in DEFAULTS (per-domain Data class) —
        # sourced from GLOBAL_DEFAULTS or directly from brand_config. Frontend
        # falls through to NEUTRAL_BRAND_DEFAULTS when nil.
        brand_global_defaults       = Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS
        brand_product_domain        = brand_config['product_domain']
        brand_support_email         = brand_config['support_email'] || brand_global_defaults[:support_email]
        brand_logo_url              = brand_config['logo_url'] || brand_global_defaults[:logo_url]
        brand_favicon_url           = brand_config['favicon_url'] || brand_global_defaults[:favicon_url]
        brand_totp_issuer           = brand_config['totp_issuer'] || brand_global_defaults[:totp_issuer]

        # Return all view variables as a hash
        {
          'authenticated' => authenticated,
          'awaiting_mfa' => awaiting_mfa,
          'baseuri' => baseuri,
          'cust' => cust,
          'description' => description,
          'development' => development,
          'diagnostics' => diagnostics,
          'display_domain' => display_domain,
          'domain_strategy' => domain_strategy,
          'features' => safe_features,
          'frontend_development' => frontend_development,
          'frontend_host' => frontend_host,
          'homepage_mode' => homepage_mode,
          'keywords' => keywords,
          'locale' => locale,
          'messages' => messages.empty? ? nil : messages,
          'no_cache' => no_cache,
          'nonce' => nonce,
          'organization' => organization,
          'page_title' => page_title,
          'script_element_id' => script_element_id,
          'sess' => sess,
          'session_email' => session_email,
          'shrimp' => shrimp,
          'site' => safe_site,
          'site_host' => site_host,
          'brand_primary_color' => brand_primary_color,
          'brand_product_name' => brand_product_name,
          'brand_corner_style' => brand_corner_style,
          'brand_font_family' => brand_font_family,
          'brand_button_text_light' => brand_button_text_light,
          'brand_allow_public_homepage' => brand_allow_public_homepage,
          'brand_allow_public_api' => brand_allow_public_api,
          'brand_product_domain' => brand_product_domain,
          'brand_support_email' => brand_support_email,
          'brand_logo_url' => brand_logo_url,
          'brand_favicon_url' => brand_favicon_url,
          'brand_totp_issuer' => brand_totp_issuer,
          'support_email' => support_email,
          'docs_host' => docs_host,
        }
      end

      # Build safe site configuration for frontend exposure
      #
      # Filters site configuration to include only whitelisted fields and removes
      # nested sensitive data like cluster credentials and authentication secrets.
      #
      # @param site_config [Hash] Raw site configuration from OT.conf
      # @return [Hash] Filtered configuration safe for frontend
      def build_safe_site_config(site_config)
        # Populate a new hash with the site config settings that are safe
        # to share with the front-end app (i.e. public).
        #
        # SECURITY: This is an opt-in approach that explicitly selects which
        # configuration values to share with the frontend while protecting
        # sensitive data. We copy only the whitelisted fields and then
        # filter specific nested sensitive data from complex structures.
        safe_site = InitializeViewVars.safe_site_fields.each_with_object({}) do |field, hash|
          field_str = field.to_s
          unless site_config.key?(field_str)
            log_metadata = {
              field: field_str,
              module: 'InitializeViewVars',
            }
            Onetime.app_logger.debug('Site config missing expected field', log_metadata)
            next
          end

          # Perform deep copy to prevent unintended mutations to the original config
          hash[field] = OT::Config.deep_clone(site_config[field_str])
        end

        # Additional filtering for nested sensitive data
        if (safe_site['authentication']) && safe_site['authentication'].is_a?(Hash)
          # Add auth mode from auth config (separate from site config)
          safe_site['authentication']['mode'] = Onetime.auth_config.mode
        end

        safe_site
      end

      # Build safe features configuration for frontend exposure
      #
      # Filters features configuration to include only safe fields and removes
      # nested sensitive data like cluster credentials.
      #
      # @param features_config [Hash] Raw features configuration from OT.conf
      # @return [Hash] Filtered configuration safe for frontend
      def build_safe_features_config(features_config)
        return {} if features_config.nil? || features_config.empty?

        # Deep copy to prevent mutations
        safe_features = OT::Config.deep_clone(features_config)

        # Remove sensitive cluster credentials from domains config
        if safe_features.dig('domains', 'cluster')
          safe_features['domains'].delete('cluster')
        end

        safe_features
      end
    end
  end
end
