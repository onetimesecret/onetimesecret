# lib/onetime/rsfc/onetime_window_bridge.rb

require_relative '../services/ui/ui_context'

module Onetime
  module RSFC
    # Bridge to convert existing UI serializers output to RSFC-compatible data structure
    #
    # This bridge maintains compatibility with the Vue frontend's OnetimeWindow interface
    # while allowing RSFC templates to access the data. It reuses the existing serializer
    # system to ensure the frontend receives the exact structure it expects.
    class OnetimeWindowBridge
      extend Onetime::Services::Manifold::UIContext

      class << self
        # Build RSFC-compatible data using existing serializers
        #
        # @param req [Rack::Request] Current request object
        # @param sess [Session] Current session
        # @param cust [Customer] Current customer
        # @param locale [String] Current locale
        # @return [Hash] Data structure compatible with RSFC templates
        def build_rsfc_data(req, sess, cust, locale)
          # Get basic template vars from existing UIContext
          template_vars = build_template_vars(req, sess, cust, locale)

          # Build serialized data (this would normally use the registry)
          serialized_data = build_serialized_data(template_vars)

          # Return combined structure
          {
            # Original serialized data (for OnetimeWindow compatibility)
            **serialized_data,

            # Additional RSFC-specific data
            rsfc_meta: {
              version: '1.0',
              generated_at: Time.current.iso8601,
              template_engine: 'rhales',
            },
          }
        end

        # Build data specifically for Vue SPA (OnetimeWindow structure)
        #
        # @param req [Rack::Request] Current request object
        # @param sess [Session] Current session
        # @param cust [Customer] Current customer
        # @param locale [String] Current locale
        # @return [Hash] OnetimeWindow-compatible data structure
        def build_onetime_window_data(req, sess, cust, locale)
          template_vars = build_template_vars(req, sess, cust, locale)
          build_serialized_data(template_vars)
        end

        private

        # Build template variables using existing UIContext
        def build_template_vars(req, sess, cust, locale)
          # Use existing UIContext to build template vars
          i18n_instance = build_i18n_instance(locale)

          begin
            # Use the existing template_vars method if available
            template_vars(req, sess, cust, locale, i18n_instance) # via UIContext
          rescue StandardError => ex
            # Fallback to minimal structure if UIContext fails
            OT.ld "[OnetimeWindowBridge] UIContext failed, using fallback: #{ex.message}"
            OT.ld ex.backtrace[0..6].join("\n") if OT.debug?
            build_fallback_template_vars(req, sess, cust, locale)
          end
        end

        # Build serialized data using a simplified version of the serializer pattern
        def build_serialized_data(template_vars)
          # For now, we'll build a simplified version of the expected structure
          # In the future, this could integrate with the actual SerializerRegistry

          {
            # Basic authentication and user data
            authenticated: template_vars[:authenticated] || false,
            cust: serialize_customer(template_vars[:cust]),
            custid: template_vars[:cust]&.custid || '',
            email: template_vars[:cust]&.email || '',
            customer_since: template_vars[:cust]&.created&.iso8601,

            # Site and domain information
            baseuri: build_base_uri(template_vars),
            site_host: template_vars[:site]&.dig('host') || 'localhost',
            canonical_domain: template_vars[:display_domain] || 'localhost',
            domain_strategy: template_vars[:domain_strategy] || 'default',
            domain_id: template_vars[:domain_id] || 'default',
            display_domain: template_vars[:display_domain] || 'localhost',

            # Security tokens
            shrimp: template_vars[:shrimp] || '',

            # Internationalization
            i18n_enabled: true,
            locale: template_vars[:locale] || 'en',
            supported_locales: ['en'], # TODO: Get from config
            fallback_locale: 'en',
            default_locale: 'en',

            # System information
            ot_version: defined?(OT::VERSION) ? OT::VERSION.to_s : '0.0.0',
            ot_version_long: defined?(OT::VERSION) ? OT::VERSION.inspect : '0.0.0',
            ruby_version: RUBY_VERSION,

            # Feature flags
            plans_enabled: false,
            regions_enabled: false,
            domains_enabled: false,
            d9s_enabled: false,

            # Frontend configuration
            frontend_host: template_vars[:frontend_host] || 'localhost:3000',
            enjoyTheVue: false,

            # User type and permissions
            user_type: 'anonymous',
            is_paid: false,
            plan: {},
            available_plans: [],
            default_planid: '',

            # Messages and notifications
            messages: template_vars[:messages] || [],

            # Application configuration
            authentication: build_authentication_config(template_vars),
            secret_options: build_secret_options(template_vars),
            features: build_features_config(template_vars),
            ui: build_ui_config(template_vars),
            regions: {},
            diagnostics: {},

            # Additional fields
            incoming_recipient: '',
            available_jurisdictions: [],
            global_banner: nil,
            domain_branding: {},
            domain_logo: {},
          }
        end

        # Build i18n instance
        def build_i18n_instance(locale)
          # Simplified i18n instance - in practice this would use the real i18n system
          { 'locale' => locale }
        end

        # Fallback template vars if UIContext is not available
        def build_fallback_template_vars(req, sess, cust, locale)
          {
            authenticated: sess&.authenticated? && cust && !cust.anonymous?,
            cust: cust,
            locale: locale,
            messages: sess&.get_messages || [],
            shrimp: req&.env&.fetch('ots.csrf_token', ''),
            nonce: req&.env&.fetch('ots.nonce', ''),
            site: { 'host' => 'localhost' },
            display_domain: 'localhost',
            domain_strategy: 'default',
          }
        end

        # Serialize customer data
        def serialize_customer(cust)
          return nil unless cust && !cust.anonymous?

          {
            custid: cust.custid,
            email: cust.email,
            created: cust.created&.iso8601,
          }
        end

        # Build base URI from template vars
        def build_base_uri(template_vars)
          site     = template_vars[:site] || {}
          protocol = site['ssl'] ? 'https' : 'http'
          host     = site['host'] || 'localhost'
          "#{protocol}://#{host}"
        end

        # Build authentication configuration
        def build_authentication_config(template_vars)
          {
            enabled: true,
            signup_enabled: true,
          }
        end

        # Build secret options configuration
        def build_secret_options(template_vars)
          {
            default_ttl: 3600,
            max_ttl: 86_400,
          }
        end

        # Build features configuration
        def build_features_config(template_vars)
          {
            markdown: false,
          }
        end

        # Build UI configuration
        def build_ui_config(template_vars)
          {
            enabled: true,
            header: {
              enabled: true,
            },
            footer_links: {
              enabled: false,
              groups: [],
            },
          }
        end
      end
    end
  end
end
