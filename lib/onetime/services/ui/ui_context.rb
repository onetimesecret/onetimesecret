# lib/onetime/services/frontend/frontend_context.rb

module Onetime
  module Services
    module Frontend
      # UIContext
      #
      # TODO: This serialization stuff is a real monkey's lunch. The whole concept
      # of opting in to accessing only safe fields was one of the main drivers for
      # the new two pronged static and dynamic config. There are still a couple
      # fields from static_conf['] that we want to expose to the frontend but
      # the entire dynamic_conf['user_interface'] can be accessed safely. There
      # is a lot of defensive fussing going here and after all the initialization
      # work to get the runtime settings all cool and nice, we can cash in on some
      # of that sweetness here.
      #
      # This module is meant to be extended and not included. That's why
      # template_vars takes the arguments it does instead of relying on
      # instance variables and their attr_reader methods.
      module UIContext

        # Define fields that are safe to expose to the frontend
        # Explicitly excluding :secret and :authenticity which contain sensitive data
        @safe_site_fields = [
          :host, :ssl, :authentication
        ].freeze

        class << self
          attr_reader :safe_site_fields
        end

        # Initialize core variables used throughout view rendering. These values
        # are the source of truth for the values that they represent. Any other
        # values that the serializers want can be derived from here.
        #
        # @param req [Rack::Request] Current request object
        # @param sess [Session] Current session
        # @param cust [Customer] Current customer
        # @param locale [String] Current locale
        # @param i18n_instance [I18n] Current I18n instance
        # @return [Hash] Collection of initialized variables
        # rubocop:disable Metrics/MethodLength
        def template_vars(req, sess, cust, locale, i18n_instance)
          # Return minimal defaults if OT.conf isn't loaded yet
          return minimal_defaults(req, sess, cust, locale) unless OT.conf

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
          development = OT.conf.fetch('development', {})
          diagnostics = OT.conf.fetch('diagnostics', {})

          user_interface = OT.conf['ui']
          api            = OT.conf['api']
          secret_options = OT.conf['secret_options']
          features       = OT.conf['features']

          # Populate a new hash with the site config settings that are safe
          # to share with the front-end app (i.e. public).
          #
          # SECURITY: This is an opt-in approach that explicitly selects which
          # configuration values to share with the frontend while protecting
          # sensitive data. We copy only the whitelisted fields and then
          # filter specific nested sensitive data from complex structures.
          safe_site = UIContext.safe_site_fields.each_with_object({}) do |field_sym, hash|
            field = field_sym.to_s
            unless site_config.key?(field)
              OT.ld "[view_vars] Site config is missing field: #{field}"
              next
            end

            # Previously we would deep copy here to prevent unintended mutations
            # to the original config but the entire static config is now deep
            # frozen before being made available.
            hash[field] = site_config[field]
          end

          # Extract values from session
          messages      = sess.nil? ? [] : sess.get_messages
          shrimp        = sess.nil? ? nil : sess.add_shrimp
          authenticated = sess && sess.authenticated? && !cust.anonymous?

          # Extract values from rack request object
          nonce           = req.env.fetch('ots.nonce', nil) # TODO: Rename to onetime.nonce
          domain_strategy = req.env.fetch('onetime.domain_strategy', :default)
          display_domain  = req.env.fetch('onetime.display_domain', nil)

          # HTML Tag vars. These are meant for the view templates themselves
          # and not the onetime state window data passed on to the Vue app (
          # although a serializer could still choose to include any of them).
          description          = i18n_instance.dig(:COMMON, :description)
          keywords             = i18n_instance.dig(:COMMON, :keywords)
          page_title           = OT.conf.dig(:ui, :header, :branding, :site_name) || 'OneTimeSecret'
          no_cache             = false
          frontend_host        = development[:frontend_host]
          frontend_development = development[:enabled]
          script_element_id    = 'onetime-state'

          # Return all view variables as a hash. Whatever is returned here
          # is made available to the serializers as view_vars.
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
            incoming: nil,
            keywords: keywords,
            locale: locale,
            messages: messages,
            no_cache: no_cache,
            nonce: nonce,
            page_title: page_title,
            script_element_id: script_element_id,
            shrimp: shrimp,
            site: safe_site,
            user_interface: user_interface,
            api: api,
            secret_options: secret_options,
            features: features,
          }
        end
        # rubocop:enable Metrics/MethodLength

        def minimal_defaults(_req, sess, cust, locale)
          {
            authenticated: false,
            cust: cust,
            locale: locale,
            messages: sess&.get_messages || [],
            no_cache: false,
            site: {},
          }
        end
      end
    end
  end
end
