require_relative 'view_helpers'

module Onetime
  module App

    class View < Mustache
      include Onetime::App::Views::ViewHelpers

      self.template_path = './templates/web'
      self.template_extension = 'html'
      self.view_namespace = Onetime::App::Views
      self.view_path = './app/web/views'

      attr_reader :req, :plan, :is_paid, :canonical_domain, :domain_strategy
      attr_accessor :sess, :cust, :locale, :messages, :form_fields, :pagename

      def initialize req, sess=nil, cust=nil, locale=nil, *args # rubocop:disable Metrics/MethodLength
        @req, @sess, @cust, @locale = req, sess, cust, locale
        @locale ||= req.env['ots.locale'] || OT.conf[:locales].first.to_s || 'en' unless req.nil?
        @messages = { :info => [], :error => [] }
        site = OT.conf.fetch(:site, {})
        is_default_locale = OT.conf[:locales].first.to_s == locale
        supported_locales = OT.conf.fetch(:locales, []).map(&:to_s)
        @canonical_domain = Onetime::DomainStrategy.normalize_canonical_domain(site) # can be nil
        @domain_strategy = req.env['onetime.domain_strategy'] # never nil

        # TODO: Make better use of fetch/dig to avoid nil checks. Esp important
        # across release versions where the config may change and existing
        # installs may not have had a chance to update theirs yet.
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

        self[:jsvars] = []

        # Add the global site banner if there is one
        self[:jsvars] << jsvar(:global_banner, OT.global_banner) if OT.global_banner

        # Pass the authentication flag settings to the frontends.
        self[:jsvars] << jsvar(:authentication, authentication)
        self[:jsvars] << jsvar(:shrimp, sess.add_shrimp) if sess

        # Only send the regions config when the feature is enabled.
        self[:jsvars] << jsvar(:regions_enabled, regions_enabled)
        self[:jsvars] << jsvar(:regions, regions) if regions_enabled

        if authenticated && cust
          self[:jsvars] << jsvar(:metadata_record_count, cust.metadata_list.length)
          self[:jsvars] << jsvar(:domains_enabled, domains_enabled) # only for authenticated

          self[:jsvars] << jsvar(:custid, cust.custid)
          self[:jsvars] << jsvar(:cust, cust.safe_dump)
          self[:jsvars] << jsvar(:email, cust.email)

          # TODO: We can remove this after we update the Account view to use
          # the value of cust.created to calculate the customer_since value
          # on-the-fly and in the time zone of the user.
          self[:jsvars] << jsvar(:customer_since, epochdom(cust.created))

          # There's no custom domain list when the feature is disabled.
          if domains_enabled
            self[:jsvars] << jsvar(:custom_domains_record_count, cust.custom_domains.length)
            self[:jsvars] << jsvar(:custom_domains, cust.custom_domains_list.collect { |obj| obj.display_domain }.sort)
          end
        end

        unless sess.nil?
          if cust.pending?
            add_message i18n[:COMMON][:verification_sent_to] + " #{cust.custid}."
          else
            add_errors sess.get_error_messages
          end

          add_messages sess.get_info_messages
          add_form_fields sess.get_form_fields!
        end

        # Link to the pricing page can be seen regardless of authentication status
        self[:jsvars] << jsvar(:plans_enabled, site.dig(:plans, :enabled) || false)
        self[:jsvars] << jsvar(:locale, @locale)
        self[:jsvars] << jsvar(:is_default_locale, is_default_locale)
        self[:jsvars] << jsvar(:supported_locales, supported_locales)

        self[:jsvars] << jsvar(:incoming_recipient, incoming_recipient)
        self[:jsvars] << jsvar(:support_host, support_host)
        self[:jsvars] << jsvar(:secret_options, secret_options)
        self[:jsvars] << jsvar(:frontend_host, frontend_host)
        self[:jsvars] << jsvar(:authenticated, authenticated)
        self[:jsvars] << jsvar(:site_host, site[:host])
        self[:jsvars] << jsvar(:canonical_domain, canonical_domain)
        self[:jsvars] << jsvar(:domain_strategy, domain_strategy)

        # The form fields hash is populated by handle_form_error so only when there's
        # been a form error in the request immediately prior to this one being served
        # now will this have any value at all. This is used to repopulate the form
        # fields with the values that were submitted so the user can try again
        # without having to re-enter everything.
        self[:jsvars] << jsvar(:form_fields, self.form_fields)

        self[:jsvars] << jsvar(:ot_version, OT::VERSION.inspect)
        self[:jsvars] << jsvar(:ruby_version, "#{OT.sysinfo.vm}-#{OT.sysinfo.ruby.join}")

        plans = Onetime::Plan.plans.transform_values do |plan|
          plan.safe_dump
        end
        self[:jsvars] << jsvar(:available_plans, plans)

        @plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
        @plan ||= Onetime::Plan.plan('anonymous')
        @is_paid = plan.paid?

        self[:jsvars] << jsvar(:plan, plan.safe_dump)
        self[:jsvars] << jsvar(:is_paid, @is_paid)
        self[:jsvars] << jsvar(:default_planid, 'basic')

        # So the list of template vars shows up sorted variable name
        self[:jsvars] = self[:jsvars].sort_by { |item| item[:name] }

        init(*args) if respond_to? :init
      end

      def i18n
        self.class.pagename ||= self.class.name.split('::').last.downcase.to_sym
        @i18n ||= {
          locale: self.locale,
          default: OT.conf[:locales].first.to_s,
          page: OT.locales[self.locale][:web][self.class.pagename],
          COMMON: OT.locales[self.locale][:web][:COMMON]
        }
      end

      def add_message msg
        messages[:info] << {type: 'info', content: msg} unless msg.to_s.empty?
      end

      def add_messages *msgs
        messages[:info].concat msgs.flatten unless msgs.flatten.empty?
      end

      def add_error msg
        messages[:error] << {type: 'error', content: msg} unless msg.to_s.empty?
      end

      def add_errors *msgs
        messages[:error].concat msgs.flatten unless msgs.flatten.empty?
      end

      def add_form_fields hsh
        (self.form_fields ||= {}).merge! hsh unless hsh.nil?
      end

      class << self
        # pagename must stay here while we use i18n method above. It populates
        # the i18n[:web][:pagename] hash with the locale translations, provided
        # the view being used has a matching name in the locales file.
        attr_accessor :pagename
      end

    end
  end
end
