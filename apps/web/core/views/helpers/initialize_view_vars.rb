# apps/web/core/views/helpers/initialize_view_vars.rb

require 'onetime/logging'

module Core
  module Views
    # InitializeViewVars
    #
    # This module is meant to be extended and not included. That's why
    # initialize_view_vars takes the arguments it does instead of relying on
    # instance variables and their attr_reader methods.
    module InitializeViewVars
      extend Onetime::Logging
      # Define fields that are safe to expose to the frontend
      # Explicitly excluding :secret and :authenticity which contain sensitive data
      @safe_site_fields = %w[
        host ssl interface domains
        secret_options authentication regions
      ]

      class << self
        attr_reader :safe_site_fields
      end
      # Initialize core variables used throughout view rendering. These values
      # are the source of truth for te values that they represent. Any other
      # values that the serializers want can be derived from here.
      #
      # @param req [Rack::Request] Current request object
      # @param i18n_instance [I18n] Current I18n instance
      # @param sess [Hash, nil] Pre-resolved session (optional, extracted from strategy_result if nil)
      # @param cust [Customer, nil] Pre-resolved customer (optional, extracted from strategy_result if nil)
      # @return [Hash] Collection of initialized variables
      def initialize_view_vars(req, i18n_instance, sess = nil, cust = nil)
        # Extract the top-level keys from the YAML configuration.
        #
        # SECURITY: This implementation follows an opt-in approach for configuration filtering.
        # We explicitly whitelist fields that are safe to share and filter nested sensitive data.
        # This prevents accidental exposure of sensitive information to the frontend.
        #
        # Sensitive data types being protected:
        # - Secret keys and credentials (:secret, nested :cluster, :colonels)
        # - Authentication tokens (:authenticity)
        # - Internal infrastructure details
        #
        site_config = OT.conf.fetch('site', {})
        features    = OT.conf.fetch('features', {})
        development = OT.conf.fetch('development', {})
        diagnostics = OT.conf.fetch('diagnostics', {})

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
            Onetime.app_logger.debug "Site config missing expected field", {
              field: field_str,
              module: "InitializeViewVars"
            }
            next
          end

          # Perform deep copy to prevent unintended mutations to the original config
          hash[field] = OT::Config.deep_clone(site_config[field_str])
        end

        # Additional filtering for nested sensitive data
        if (safe_site['domains']) && safe_site['domains'].is_a?(Hash)
          safe_site['domains'].delete('cluster')
        end

        if (safe_site['authentication']) && safe_site['authentication'].is_a?(Hash)
          safe_site['authentication'].delete('colonels')
        end

        # Extract values from session
        #
        # Use pre-resolved sess/cust if provided (from BaseView#initialize),
        # otherwise extract from strategy_result or fallback values
        if sess.nil? || cust.nil?
          strategy_result = req.env.fetch('otto.strategy_result', nil)

          if strategy_result
            # Normal flow: Otto ran, strategy_result available
            sess ||= strategy_result.session
            cust ||= strategy_result.user || Onetime::Customer.anonymous
            authenticated = strategy_result.authenticated? || false
          else
            # Error recovery flow: Otto didn't run, use fallback values
            begin
              sess ||= req.session
            rescue NoMethodError, RuntimeError
              sess = {}
            end
            cust ||= Onetime::Customer.anonymous
            authenticated = false
          end
        else
          # Using pre-resolved values from BaseView#initialize
          strategy_result = req.env.fetch('otto.strategy_result', nil)
          authenticated = strategy_result&.authenticated? || false
        end

        # Rack::Protection::AuthenticityToken stores CSRF token in session[:csrf]
        # It generates the token on first access if not present
        shrimp = sess&.[](:csrf) || sess&.[]('csrf')

        awaiting_mfa  = sess&.[]('awaiting_mfa') || false

        # DEBUG: Log session state
        Onetime.session_logger.debug "Session", {
          account_id: sess&.[]('account_id'),
          external_id: sess&.[]('external_id'),
          module: "InitializeViewVars",
          awaiting_mfa: awaiting_mfa,
          authenticated: authenticated
        }

        # When awaiting_mfa is true, user has NOT completed authentication
        # Do NOT load customer from Redis - they don't have access yet
        # The frontend will show minimal MFA prompt using email from session
        session_email = sess&.[]('email')

        # Extract values from rack request object
        nonce           = req.env.fetch('onetime.nonce', nil)
        domain_strategy = req.env.fetch('onetime.domain_strategy', :default)
        display_domain  = req.env.fetch('onetime.display_domain', nil)
        locale          = req.env.fetch('otto.locale', OT.default_locale)

        # HTML Tag vars. These are meant for the view templates themselves
        # and not the onetime state window data passed on to the Vue app (
        # although a serializer could still choose to include any of them).
        description          = i18n_instance[:COMMON][:description]
        keywords             = i18n_instance[:COMMON][:keywords]
        page_title           = 'Onetime Secret' # TODO: Implement as config setting
        no_cache             = false
        frontend_host        = development['frontend_host']
        frontend_development = development['enabled']
        script_element_id    = 'onetime-state'

        # URI helpers for templates
        site_host            = safe_site['host']
        base_scheme          = safe_site['ssl'] ? 'https://' : 'http://'
        baseuri              = base_scheme + site_host

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
          'frontend_development' => frontend_development,
          'frontend_host' => frontend_host,
          'keywords' => keywords,
          'locale' => locale,
          'messages' => nil,
          'no_cache' => no_cache,
          'nonce' => nonce,
          'page_title' => page_title,
          'script_element_id' => script_element_id,
          'session_email' => session_email,
          'shrimp' => shrimp,
          'site' => safe_site,
          'site_host' => site_host,
        }
      end
    end
  end
end
