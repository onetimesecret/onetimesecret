# lib/onetime/services/ui/ui_context.rb

require 'rhales'

module Onetime
  module Services
    # UIContext extends Rhales::Context with OneTimeSecret-specific business logic
    #
    # This class contains the authoritative business logic ported from
    # Core::Views::BaseView#initialize. It serves as the single source of truth
    # for all template variables and OnetimeWindow data generation.
    #
    # Key responsibilities:
    # - Customer authentication and plan information
    # - Domain strategy and custom domain handling
    # - Feature flags and configuration exposure
    # - Internationalization settings
    # - Site branding and UI configuration
    # - Development and diagnostics settings
    #
    class UIContext < Rhales::Context
      # include V2::Logic::UriHelpers # TODO2: Some window state values come from these methods

      attr_reader :plan, :is_paid, :canonical_domain, :display_domain,
        :domain_strategy, :domain_id, :domain_branding, :domain_logo, :custom_domain

      def initialize(req, sess = nil, cust = nil, locale_override = nil, props: {})
        # Set up domain and customer information first
        setup_domain_info(req)
        setup_customer_info(req, sess, cust)

        OT.li "[UIContext] Initializing UIContext (#{req.env['ots.nonce']})"
        # Build the complete business data with OnetimeWindow structure
        onetime_window = build_onetime_window_data(req, sess, @cust, locale_override)
        enhanced_props = props.merge(onetime_window: onetime_window)

        # Call parent constructor with enhanced data
        super(req, sess, @cust, locale_override, props: enhanced_props)
      end

      private

      # Set up domain-related instance variables
      def setup_domain_info(req)
        return unless req

        @canonical_domain = Onetime::DomainStrategy.canonical_domain
        @domain_strategy  = req.env.fetch('onetime.domain_strategy', :default)
        @display_domain   = req.env.fetch('onetime.display_domain', nil)

        return unless @domain_strategy == :custom

        @custom_domain   = V2::CustomDomain.from_display_domain(@display_domain)
        @domain_id       = @custom_domain&.domainid
        @domain_branding = (@custom_domain&.brand&.hgetall || {}).to_h
        @domain_logo     = (@custom_domain&.logo&.hgetall || {}).to_h
      end

      # Set up customer and plan information
      def setup_customer_info(_req, sess, cust)
        @cust             = cust || V2::Customer.anonymous
        authenticated     = sess && sess.authenticated? && !@cust.anonymous?
        @is_authenticated = authenticated
      end

      # Build complete OnetimeWindow data structure
      # This is the authoritative business logic ported from Core::Views::BaseView#initialize
      # rubocop:disable Lint/UselessAssignment
      def build_onetime_window_data(req, sess, cust, locale_override)
        # Return minimal defaults if OT.conf isn't loaded yet
        return minimal_onetime_window(req, sess, cust, locale_override) unless defined?(OT) && OT.conf

        locale      = determine_final_locale(req, locale_override)

        # From static config
        site                     = OT.conf.fetch('site', {})
        capabilities             = OT.conf.fetch('capabilities', {})
        storage                  = OT.conf.fetch('storage', {})
        mail_validation_defaults = OT.conf.dig('mail', 'validation', 'defaults') || {}
        features                 = OT.conf.fetch('features', {})
        logging                  = OT.conf.fetch('logging', {})
        i18n                     = OT.conf.fetch('i18n', {})
        development              = OT.conf.fetch('development', {})
        experimental             = OT.conf.fetch('experimental', {})
        billing                  = OT.conf.fetch('billing', {})

        # From mutable config
        ui              = OT.conf.fetch('ui', {})
        api             = OT.conf.fetch('api', {})
        secret_options  = OT.conf.fetch('secret_options', {})
        limits          = OT.conf.fetch('limits', {})
        mail_validation = OT.conf.dig('mail', 'validation') || {}

        # Extract configuration sections
        domains                = features.fetch('domains', {})
        regions                = features.fetch('regions', {})
        incoming               = features.fetch('incoming', {})
        static_authentication  = site.fetch('authentication', {})
        mutable_authentication = ui.fetch('authentication', {})

        # Frontend development settings
        frontend_development = development['enabled'] || false
        frontend_host        = development['frontend_host'] || ''

        # Authentication and customer state
        authentication = {
          'enabled' => static_authentication['enabled'],
          'signin' => mutable_authentication['signin'],
          'signup' => mutable_authentication['signup'],
        }

        # Features
        incoming_recipient = incoming.fetch('email', nil)
        domains_enabled = domains['enabled'] || false
        regions_enabled = regions['enabled'] || false

        # Get locale information
        display_locale    = determine_display_locale(locale)
        is_default_locale = display_locale == locale

        # Get messages and shrimp
        messages = sess&.get_messages || []
        shrimp = sess&.add_shrimp


        # Build the complete jsvars structure (OnetimeWindow format)
        jsvars = build_base_jsvars(req, ui, authentication, frontend_host, frontend_development)

        # Add authentication-dependent data
        add_authentication_data(jsvars, cust, domains_enabled)

        # Add configuration and feature flags
        add_configuration_data(
          jsvars,
          site,
          secret_options,
          regions,
          regions_enabled,
          incoming_recipient,
        )

        jsvars[:baseuri] = baseuri(site)

        # Add locale and i18n data
        add_locale_data(jsvars, display_locale, is_default_locale)

        # Add diagnostics data
        add_diagnostics_data(jsvars)

        # Add domain and branding data
        add_domain_data(jsvars)

        # Add plan and version data
        add_plan_and_version_data(jsvars)

        # Add messages and shrimp
        jsvars[:messages] = messages
        jsvars[:shrimp] = shrimp

        jsvars
      end
      # rubocop:enable Lint/UselessAssignment

      def baseuri(site)
        scheme = site['ssl'] ? 'https://' : 'http://'
        host   = site['host']
        [scheme, host].join
      end

      # Determine the final locale to use
      def determine_final_locale(req, locale_override)
        if locale_override
          locale_override
        elsif req && req.env['ots.locale']
          req.env['ots.locale']
        else
          OT.default_locale || 'en'
        end
      end

      # Determine display locale (considering custom domain branding)
      def determine_display_locale(locale)
        if @domain_strategy == :custom && @domain_branding
          domain_locale = @domain_branding.fetch('locale', nil)
          return domain_locale if domain_locale
        end
        locale
      end

      # Build base jsvars with core settings
      def build_base_jsvars(req, ui, authentication, frontend_host, frontend_development)
        jsvars = {}

        # Add the nonce if it exists
        jsvars[:nonce] = req&.env&.fetch('ots.nonce', nil)

        # Add global banner if present
        jsvars[:global_banner] = '' # OT.global_banner if defined?(OT) && OT.respond_to?(:) &&OT.global_banner

        # Add UI settings
        jsvars[:ui] = ui

        # Authentication settings
        jsvars[:authentication] = authentication

        # Frontend settings
        jsvars[:frontend_host]        = frontend_host
        jsvars[:frontend_development] = frontend_development

        jsvars
      end

      # Add authentication-dependent customer data
      def add_authentication_data(jsvars, cust, domains_enabled)
        # Keys that should always exist (even if nil)
        ensure_exist = [:domains_enabled, :custid, :cust, :email, :customer_since, :custom_domains]

        authenticated = @is_authenticated

        jsvars[:domains_enabled] = domains_enabled
        jsvars[:authenticated]   = authenticated

        if authenticated && cust
          jsvars[:custid]         = cust.custid
          jsvars[:cust]           = cust.safe_dump
          jsvars[:email]          = cust.email
          jsvars[:customer_since] = epochdom(cust.created) if respond_to?(:epochdom)

          # Custom domains for authenticated users
          if domains_enabled
            custom_domains          = cust.custom_domains_list.filter_map do |obj|
              # Log unverified domains but allow them for now
              if !obj.ready? && defined?(OT) && OT.respond_to?(:li)
                OT.li "[custom_domains] Allowing unverified domain: #{obj.display_domain} (#{obj.verified}/#{obj.resolving})"
              end
              obj.display_domain
            end
            jsvars[:custom_domains] = custom_domains.sort
          end
        else
          # Set ensure_exist keys to nil for unauthenticated users
          ensure_exist.each do |key|
            jsvars[key] = nil
          end
        end
      end

      # Add configuration and feature data
      def add_configuration_data(jsvars, site, secret_options, regions, regions_enabled, incoming_recipient)
        # Plans and pricing
        jsvars[:plans_enabled] = site.dig('plans', 'enabled') || false

        # Regions (only when enabled)
        jsvars[:regions_enabled] = regions_enabled
        jsvars[:regions]         = regions if regions_enabled

        # Contact and support
        jsvars[:incoming_recipient] = incoming_recipient
        jsvars[:secret_options]     = secret_options

        # Site host
        jsvars[:site_host] = site[:host]
      end

      # Add locale and internationalization data
      def add_locale_data(jsvars, display_locale, is_default_locale)
        jsvars[:locale]            = display_locale
        jsvars[:is_default_locale] = is_default_locale

        return unless defined?(OT)

        # TODO2: i18n configuration
        jsvars[:default_locale]    = 'en' # OT.default_locale if OT.respond_to?(:default_locale)
        jsvars[:fallback_locale]   = 'en' # OT.fallback_locale if OT.respond_to?(:fallback_locale)
        jsvars[:supported_locales] = %w[en de_AT fr_CA fr_FR] # OT.supported_locales if OT.respond_to?(:supported_locales)
        jsvars[:i18n_enabled]      = true # OT.i18n_enabled if OT.respond_to?(:i18n_enabled)
      end

      # Add diagnostics and monitoring data
      def add_diagnostics_data(jsvars)
        return unless defined?(OT) && OT.conf

        # TODO2: diannostics config
        sentry               = OT.conf.dig('diagnostics', :sentry) || {}
        jsvars[:d9s_enabled] = false # OT.d9s_enabled if OT.respond_to?(:d9s_enabled)

        return unless defined?(Onetime) && Onetime.respond_to?(:with_diagnostics)

        Onetime.with_diagnostics do
          config               = sentry.fetch('frontend', {})
          jsvars[:diagnostics] = {
            sentry: config,
          }
        end
      end

      # Add domain strategy and branding data
      def add_domain_data(jsvars)
        jsvars[:canonical_domain] = @canonical_domain
        jsvars[:domain_strategy]  = @domain_strategy
        jsvars[:domain_id]        = @domain_id
        jsvars[:domain_branding]  = @domain_branding
        jsvars[:domain_logo]      = @domain_logo
        jsvars[:display_domain]   = @display_domain
      end

      # Add plan and version information
      def add_plan_and_version_data(jsvars)
        # Available plans
        # if defined?(Onetime::Plan) && Onetime::Plan.respond_to?(:plans)
        #   # plans                    = Onetime::Plan.plans.transform_values do |plan|
        #   #   plan.safe_dump
        #   # end
        #
        #   # Used only in src/stores/customerStore.ts
        #   #
        #   # jsvars[:available_plans] = plans
        # end

        # Current plan
        # jsvars[:plan]           = @plan.safe_dump if @plan
        jsvars[:is_paid]        = @is_paid || false

        # Version information
        if defined?(OT::VERSION)
          jsvars[:ot_version] = OT::VERSION.inspect
        end

        if defined?(OT) && OT.respond_to?(:sysinfo)
          jsvars[:ruby_version] = "#{OT.sysinfo.vm}-#{OT.sysinfo.ruby.join}"
        end
      end

      # Minimal fallback when OT.conf is not available
      def minimal_onetime_window(req, sess, cust, locale)
        {
          authenticated: false,
          cust: cust,
          locale: locale || 'en',
          messages: sess&.get_messages || [],
          nonce: req&.env&.fetch('ots.nonce', nil),
          site_host: nil,
          frontend_host: '',
          frontend_development: false,
        }
      end

      # Get variable value with onetime_window prefix support
      def resolve_variable(variable_path)
        # Handle direct onetime_window reference
        if variable_path == 'onetime_window'
          return get('onetime_window')
        end

        # Handle nested onetime_window paths like onetime_window.authenticated
        if variable_path.start_with?('onetime_window.')
          nested_path  = variable_path.sub('onetime_window.', '')
          onetime_data = get('onetime_window')
          return nil unless onetime_data.is_a?(Hash)

          # Navigate nested path in onetime_window data
          path_parts    = nested_path.split('.')
          current_value = onetime_data

          path_parts.each do |part|
            case current_value
            when Hash
              current_value = current_value[part] || current_value[part.to_sym]
            else
              return nil
            end
            return nil if current_value.nil?
          end

          return current_value
        end

        # Fall back to parent implementation
        get(variable_path)
      end

      class << self
        # Factory method matching Rhales::Context.for_view signature
        def for_view(req, sess, cust, locale, **props)
          new(req, sess, cust, locale, props: props)
        end

        # Factory method for minimal testing context
        def minimal(props: {})
          new(nil, nil, nil, 'en', props: props)
        end
      end
    end
  end
end
