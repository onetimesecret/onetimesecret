# apps/web/core/views/helpers/initialize_view_vars.rb

module Core
  module Views


    # InitializeViewVars
    #
    # This module is meant to be extended and not included. That's why
    # initialize_view_vars takes the arguments it does instead of relying on
    # instance variables and their attr_reader methods.
    module InitializeViewVars
      # Define fields that are safe to expose to the frontend
      # Explicitly excluding :secret and :authenticity which contain sensitive data
      @safe_site_fields = [
        :host, :ssl, :plans, :interface, :domains,
        :secret_options, :authentication, :support, :regions
      ]

      class << self
        attr_reader :safe_site_fields
      end
      # Initialize core variables used throughout view rendering. These values
      # are the source of truth for te values that they represent. Any other
      # values that the serializers want can be derived from here.
      #
      # @param req [Rack::Request] Current request object
      # @param sess [Session] Current session
      # @param cust [Customer] Current customer
      # @param locale [String] Current locale
      # @param i18n_instance [I18n] Current I18n instance
      # @return [Hash] Collection of initialized variables
      def initialize_view_vars(req, sess, cust, locale, i18n_instance)

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
        site_config = OT.conf.fetch(:site, {})
        incoming = OT.conf.fetch(:incoming, {})
        development = OT.conf.fetch(:development, {})
        diagnostics = OT.conf.fetch(:diagnostics, {})

        # Populate a new hash with the site config settings that are safe
        # to share with the front-end app (i.e. public).
        #
        # SECURITY: This is an opt-in approach that explicitly selects which
        # configuration values to share with the frontend while protecting
        # sensitive data. We copy only the whitelisted fields and then
        # filter specific nested sensitive data from complex structures.
        safe_site = InitializeViewVars.safe_site_fields.each_with_object({}) do |field, hash|
          unless site_config.key?(field)
            OT.ld "[view_vars] Site config is missing field: #{field}"
            next
          end

          # Perform deep copy to prevent unintended mutations to the original config
          hash[field] = Marshal.load(Marshal.dump(site_config[field]))
        end

        # Additional filtering for nested sensitive data
        if safe_site[:domains]
          safe_site[:domains].delete(:cluster) if safe_site[:domains].is_a?(Hash)
        end

        if safe_site[:authentication]
          safe_site[:authentication].delete(:colonels) if safe_site[:authentication].is_a?(Hash)
        end

        # Extract values from session
        messages = sess.nil? ? [] : sess.get_messages
        shrimp = sess.nil? ? nil : sess.add_shrimp
        authenticated = sess && sess.authenticated? && !cust.anonymous?

        # Extract values from rack request object
        nonce = req.env.fetch('ots.nonce', nil) # TODO: Rename to onetime.nonce
        domain_strategy = req.env.fetch('onetime.domain_strategy', :default)
        display_domain = req.env.fetch('onetime.display_domain', nil)

        # HTML Tag vars. These are meant for the view templates themselves
        # and not the onetime state window data passed on to the Vue app (
        # although a serializer could still choose to include any of them).
        description = i18n_instance[:COMMON][:description]
        keywords = i18n_instance[:COMMON][:keywords]
        # Use the display domain name for branded instances, otherwise use the default app name.
        # This provides a default title for initial page load before Vue takes over title management.
        page_title = display_domain || site_config.dig(:host, :name) || "Onetime Secret"
        no_cache = false
        frontend_host = development[:frontend_host]
        frontend_development = development[:enabled]
        script_element_id = 'onetime-state'

        # Return all view variables as a hash
        {
          authenticated: authenticated,
          cust: cust,
          description: description,
          development: development,
          diagnostics: diagnostics,
          display_domain: display_domain,
          domain_strategy: domain_strategy,
          frontend_development: frontend_development,
          frontend_host: frontend_host,
          incoming: incoming,
          keywords: keywords,
          locale: locale,
          messages: messages,
          no_cache: no_cache,
          nonce: nonce,
          page_title: page_title,
          script_element_id: script_element_id,
          shrimp: shrimp,
          site: safe_site,
        }
      end
    end
  end
end
