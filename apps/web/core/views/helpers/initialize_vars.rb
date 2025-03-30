# apps/web/core/views/helpers/initialize_vars.rb

module Core
  module Views
    module InitializeVarsHelpers
      # Initialize core variables used throughout view rendering. These values
      # are the source of truth for te values that they represent. Any other
      # values that the serializers want can be derived from here.
      #
      # @param req [Rack::Request] Current request object
      # @param sess [Session] Current session
      # @param cust [Customer] Current customer
      # @param locale [String] Current locale
      # @return [Hash] Collection of initialized variables
      def initialize_vars(req, sess, cust, locale)

        # Extract the top-level keys from the YAML configuration
        site = OT.conf.fetch(:site, {})
        incoming = OT.conf.fetch(:incoming, {})
        development = OT.conf.fetch(:development, {})
        diagnostics = OT.conf.fetch(:diagnostics, {})

        # Everything in site is safe to share with the
        # frontend, except for these two keys.
        site.delete(:secret)
        site.delete(:authenticity)
        site.fetch(:authentication, {}).delete(:colonels)

        # Extract values from session
        messages = sess.nil? ? [] : sess.get_messages
        shrimp = sess.nil? ? nil : sess.add_shrimp
        authenticated = sess && sess.authenticated? && !cust.anonymous?

        # Extract values from rack request object
        nonce = req.env.fetch('ots.nonce', nil) # TODO: Rename to onetime.nonce
        domain_strategy = req.env.fetch('onetime.domain_strategy', :default)
        display_domain = req.env.fetch('onetime.display_domain', nil)

        # Return all variables as a hash
        {
          authenticated: authenticated,
          # authentication: authentication,
          cust: cust,
          development: development,
          display_domain: display_domain,
          # domains: domains,
          # domains_enabled: domains_enabled,
          # frontend_development: frontend_development,
          # frontend_host: frontend_host,
          incoming: incoming,
          # interface: interface,
          locale: locale,
          messages: messages,
          nonce: nonce,
          # regions: regions,
          # regions_enabled: regions_enabled,
          # secret_options: secret_options,
          diagnostics: diagnostics,
          shrimp: shrimp,
          site: site,
          # support_host: support_host,
        }
      end
    end
  end
end
