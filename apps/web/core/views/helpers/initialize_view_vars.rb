# apps/web/core/views/helpers/initialize_view_vars.rb

module Core
  module Views
    # InitializeViewVars
    #
    # This module is meant to be extended and not included. That's why
    # initialize_view_vars takes the arguments it does instead of relying on
    # instance variables and their attr_reader methods.
    module InitializeViewVars
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

        # Extract the top-level keys from the YAML configuration
        site = OT.conf.fetch(:site, {})
        incoming = OT.conf.fetch(:incoming, {})
        development = OT.conf.fetch(:development, {})
        diagnostics = OT.conf.fetch(:diagnostics, {})

        # Everything in site is safe to share with the
        # frontend, except for these keys.
        site.delete(:secret)
        site.delete(:authenticity)
        site.fetch(:domains, {}).delete(:cluster)
        site.fetch(:authentication, {}).delete(:colonels)

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
        page_title = "Onetime Secret" # TODO: Implement as config setting
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
          site: site,
        }
      end
    end
  end
end
