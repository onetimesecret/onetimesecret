# lib/onetime/app/web/views/base.rb

require_relative 'view_helpers'
require_relative 'vite_helpers'

module Onetime
  module App

    class View < Mustache
      include Onetime::App::Views::ViewHelpers
      include Onetime::App::Views::ViteHelpers
      include Onetime::TimeUtils

      self.template_path = './templates/web'
      self.template_extension = 'html'
      self.view_namespace = Onetime::App::Views
      self.view_path = './app/web/views'

      attr_reader :req, :plan, :is_paid, :canonical_domain, :display_domain, :domain_strategy
      attr_reader :domain_id, :domain_branding, :domain_logo, :custom_domain
      attr_accessor :sess, :cust, :locale, :messages, :form_fields, :pagename

      def initialize req, sess=nil, cust=nil, locale=nil, *args # rubocop:disable Metrics/MethodLength
        @req, @sess, @cust, @locale = req, sess, cust, locale
        @locale ||= req.env['ots.locale'] || OT.default_locale || 'en' unless req.nil?
        @messages ||= []
        site = OT.conf.fetch(:site, {})
        is_default_locale = OT.default_locale == @locale

        @canonical_domain = Onetime::DomainStrategy.canonical_domain
        @domain_strategy = req.env.fetch('onetime.domain_strategy', :default) # never null
        @display_domain = req.env.fetch('onetime.display_domain', nil) # can be nil
        if @domain_strategy == :custom
          @custom_domain = OT::CustomDomain.from_display_domain(@display_domain)
          @domain_id = custom_domain&.domainid
          @domain_branding = (custom_domain&.brand&.hgetall || {}).to_h # bools are strings
          @domain_logo = (custom_domain&.logo&.hgetall || {}).to_h # ditto
        end

        secret_options = site.fetch(:secret_options, {})
        domains = site.fetch(:domains, {})
        regions = site.fetch(:regions, {})
        authentication = site.fetch(:authentication, {})
        support_host = site.dig(:support, :host) # defaults to nil
        incoming_recipient = OT.conf.dig(:incoming, :email)

        # If not set, the frontend_host is the same as the site_host and
        # we can leave the absolute path empty as-is without a host.
        development = OT.conf.fetch(:development, {})
        frontend_development = development[:enabled] || false
        frontend_host = development[:frontend_host] || ''

        cust ||= OT::Customer.anonymous
        authenticated = sess && sess.authenticated? && ! cust.anonymous?

        domains_enabled = domains[:enabled] || false
        regions_enabled = regions[:enabled] || false

        # Regular template vars used one
        self[:description] = i18n[:COMMON][:description]
        self[:keywords] = i18n[:COMMON][:keywords]
        self[:page_title] = "Onetime Secret"
        self[:frontend_host] = frontend_host
        self[:frontend_development] = frontend_development
        self[:no_cache] = false

        self[:jsvars] = {}

        # Diagnostics
        sentry = OT.conf.dig(:diagnostics, :sentry) || {}
        self[:jsvars][:d9s_enabled] = jsvar(OT.d9s_enabled) # pass global flag
        Onetime.with_diagnostics do
          config = sentry.fetch(:frontend, {})
          self[:jsvars][:diagnostics] = {
            # e.g. {dsn: "https://...", ...}
            sentry: jsvar(config)
          }
        end

        # Add the nonce to the jsvars hash if it exists. See `carefully`.
        self[:nonce] = req.env.fetch('ots.nonce', nil)

        # Add the global site banner if there is one
        self[:jsvars][:global_banner] = jsvar(OT.global_banner) if OT.global_banner

        # Pass the authentication flag settings to the frontends.
        self[:jsvars][:authentication] = jsvar(authentication) # nil is okay
        self[:jsvars][:shrimp] = jsvar(sess.add_shrimp) if sess

        # Only send the regions config when the feature is enabled.
        self[:jsvars][:regions_enabled] = jsvar(regions_enabled)
        self[:jsvars][:regions] = jsvar(regions) if regions_enabled

        # Ensure that these keys are always present in jsvars, even if nil
        ensure_exist = [:domains_enabled, :custid, :cust, :email, :customer_since, :custom_domains]

        self[:jsvars][:domains_enabled] = jsvar(domains_enabled) # only for authenticated

        if authenticated && cust
          self[:jsvars][:custid] = jsvar(cust.custid)
          self[:jsvars][:cust] = jsvar(cust.safe_dump)
          self[:jsvars][:email] = jsvar(cust.email)

          # TODO: We can remove this after we update the Account view to use
          # the value of cust.created to calculate the customer_since value
          # on-the-fly and in the time zone of the user.
          self[:jsvars][:customer_since] = jsvar(epochdom(cust.created))

          # There's no custom domain list when the feature is disabled.
          if domains_enabled
            custom_domains = cust.custom_domains_list.filter_map do |obj|
              # Only verified domains that resolve
              unless obj.ready?
                # For now just log until we can reliably re-attempt verification and
                # have some visibility which customers this will affect. We've made
                # the verification more stringent so currently many existing domains
                # would return obj.ready? == false.
                OT.li "[custom_domains] Allowing unverified domain: #{obj.display_domain} (#{obj.verified}/#{obj.resolving})"
              end

              obj.display_domain
            end
            self[:jsvars][:custom_domains] = jsvar(custom_domains.sort)
          end
        else
          # We do this so that in our typescript we can assume either a value
          # or nil (null), avoiding undefined altogether.
          ensure_exist.each do |key|
            self[:jsvars][key] = jsvar(nil)
          end
        end

        @messages = sess.get_messages || [] unless sess.nil?

        # Link to the pricing page can be seen regardless of authentication status
        self[:jsvars][:plans_enabled] = jsvar(site.dig(:plans, :enabled) || false)
        self[:jsvars][:locale] = jsvar(@locale)
        self[:jsvars][:is_default_locale] = jsvar(is_default_locale)
        self[:jsvars][:default_locale] = jsvar(OT.default_locale)
        self[:jsvars][:fallback_locale] = jsvar(OT.fallback_locale)
        self[:jsvars][:supported_locales] = jsvar(OT.supported_locales)

        self[:jsvars][:incoming_recipient] = jsvar(incoming_recipient)
        self[:jsvars][:support_host] = jsvar(support_host)
        self[:jsvars][:secret_options] = jsvar(secret_options)
        self[:jsvars][:frontend_host] = jsvar(frontend_host)
        self[:jsvars][:authenticated] = jsvar(authenticated)
        self[:jsvars][:site_host] = jsvar(site[:host])
        self[:jsvars][:canonical_domain] = jsvar(canonical_domain)
        self[:jsvars][:domain_strategy] = jsvar(domain_strategy)
        self[:jsvars][:domain_id] = jsvar(domain_id)
        self[:jsvars][:domain_branding] = jsvar(domain_branding)
        self[:jsvars][:domain_logo] = jsvar(domain_logo)
        self[:jsvars][:display_domain] = jsvar(display_domain)

        self[:jsvars][:ot_version] = jsvar(OT::VERSION.inspect)
        self[:jsvars][:ruby_version] = jsvar("#{OT.sysinfo.vm}-#{OT.sysinfo.ruby.join}")

        self[:jsvars][:messages] = jsvar(self[:messages])

        plans = Onetime::Plan.plans.transform_values do |plan|
          plan.safe_dump
        end
        self[:jsvars][:available_plans] = jsvar(plans)

        @plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
        @plan ||= Onetime::Plan.plan('anonymous')
        @is_paid = plan.paid?

        self[:jsvars][:plan] = jsvar(plan.safe_dump)
        self[:jsvars][:is_paid] = jsvar(@is_paid)
        self[:jsvars][:default_planid] = jsvar('basic')

        # Serialize the jsvars hash to JSON and this is the final window
        # object that will be passed to the frontend.
        self[:window] = self[:jsvars].to_json

        init(*args) if respond_to? :init
      end

      def i18n
        pagename = self.class.pagename
        messages = OT.locales.fetch(self.locale, {})

        # If we don't have translations for the requested locale, fall back.
        if messages.empty?
          translated_locales = OT.locales.keys
          OT.le "%{name} %{loc} not found in %{avail} (%{supp})" % {
            name: "[#{pagename}.i18n]",
            loc: self.locale,
            avail: translated_locales,
            supp: OT.supported_locales
          }
          messages = OT.locales.fetch(OT.default_locale, {})
        end

        @i18n ||= {
          locale: self.locale,
          default: OT.default_locale,
          page: messages[:web].fetch(pagename, {}),
          COMMON: messages[:web][:COMMON],
        }
      end

      # Add notification message to be displayed in StatusBar component
      # @param msg [String] message content to be displayed
      # @param type [String] type of message, one of: info, error, success (default: 'info')
      # @return [Array<Hash>] array containing message objects {type: String, content: String}
      def add_message msg, type='info'
        messages << {type: type, content: msg}
      end

      # Add error message to be displayed in StatusBar component
      # @param msg [String] error message content to be displayed
      # @return [Array<Hash>] array containing message objects {type: String, content: String}
      def add_error msg
        add_message(msg, 'error')
      end

      class << self
        # pagename must stay here while we use i18n method above. It populates
        # the i18n[:web][:pagename] hash with the locale translations, provided
        # the view being used has a matching name in the locales file.
        def pagename
          @pagename ||= self.name.split('::').last.downcase.to_sym
        end
      end

    end
  end
end
