# apps/web/core/views/helpers/initialize_vars.rb

module Core
  module Views
    module InitializeVarsHelpers
      # Initialize core variables used throughout view rendering
      # @param req [Rack::Request] Current request object
      # @param sess [Session] Current session
      # @param cust [Customer] Current customer
      # @param locale [String] Current locale
      # @return [Hash] Collection of initialized variables
      def initialize_core_vars(req, sess, cust, locale)
        site = OT.conf.fetch(:site, {})

        # Domain configuration
        canonical_domain = Onetime::DomainStrategy.canonical_domain
        domain_strategy = req.env.fetch('onetime.domain_strategy', :default)
        display_domain = req.env.fetch('onetime.display_domain', nil)

        # Custom domain handling
        domain_id = nil
        domain_branding = {}
        domain_logo = {}
        custom_domain = nil
        display_locale = nil

        if domain_strategy == :custom
          custom_domain = V2::CustomDomain.from_display_domain(display_domain)
          domain_id = custom_domain&.domainid
          domain_branding = (custom_domain&.brand&.hgetall || {}).to_h
          domain_logo = (custom_domain&.logo&.hgetall || {}).to_h

          domain_locale = domain_branding.fetch('locale', nil)
          display_locale = domain_locale
        end

        display_locale ||= locale
        is_default_locale = display_locale == locale

        # Site configuration values
        interface = site.fetch(:interface, {})
        secret_options = site.fetch(:secret_options, {})
        domains = site.fetch(:domains, {})
        regions = site.fetch(:regions, {})
        authentication = site.fetch(:authentication, {})
        support_host = site.dig(:support, :host)
        incoming_recipient = OT.conf.dig(:incoming, :email)

        # Frontend configuration
        development = OT.conf.fetch(:development, {})
        frontend_development = development[:enabled] || false
        frontend_host = development[:frontend_host] || ''

        # User state
        cust ||= V2::Customer.anonymous
        authenticated = sess && sess.authenticated? && !cust.anonymous?

        # Feature flags
        domains_enabled = domains[:enabled] || false
        regions_enabled = regions[:enabled] || false

        # Return all variables as a hash
        {
          canonical_domain: canonical_domain,
          domain_strategy: domain_strategy,
          display_domain: display_domain,
          domain_id: domain_id,
          domain_branding: domain_branding,
          domain_logo: domain_logo,
          custom_domain: custom_domain,
          display_locale: display_locale,
          is_default_locale: is_default_locale,
          interface: interface,
          secret_options: secret_options,
          domains: domains,
          regions: regions,
          authentication: authentication,
          support_host: support_host,
          incoming_recipient: incoming_recipient,
          frontend_development: frontend_development,
          frontend_host: frontend_host,
          cust: cust,
          authenticated: authenticated,
          domains_enabled: domains_enabled,
          regions_enabled: regions_enabled
        }
      end
    end
  end
end
