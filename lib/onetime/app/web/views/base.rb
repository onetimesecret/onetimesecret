require_relative 'view_helpers'

module Onetime
  class App
    class View < Mustache
      include Onetime::App::Views::ViewHelpers

      self.template_path = './templates/web'
      self.template_extension = 'html'
      self.view_namespace = Onetime::App::Views
      self.view_path = './app/web/views'

      attr_reader :req, :plan, :is_paid
      attr_accessor :sess, :cust, :locale, :messages, :form_fields, :pagename

      def initialize req, sess=nil, cust=nil, locale=nil, *args # rubocop:disable Metrics/MethodLength
        @req, @sess, @cust, @locale = req, sess, cust, locale
        @locale ||= req.env['ots.locale'] || OT.conf[:locales].first.to_s || 'en' unless req.nil?
        @messages = { :info => [], :error => [] }
        is_default_locale = OT.conf[:locales].first.to_s == locale

        # TODO: Make better use of fetch/dig to avoid nil checks. Esp important
        # across release versions where the config may change.
        site = OT.conf.fetch(:site, {})
        domains = site.fetch(:domains, {})
        authentication = site.fetch(:authentication, {})

        # If not set, the frontend_host is the same as the site_host and
        # we can leave the absolute path empty as-is without a host.
        development = OT.conf.fetch(:development, {})
        frontend_development = development[:enabled] || false
        frontend_host = development[:frontend_host] || ''

        cust ||= OT::Customer.anonymous
        authenticated = sess && sess.authenticated? && ! cust.anonymous?

        self[:js], self[:css] = [], []
        self[:is_default_locale] = is_default_locale
        self[:supported_locales] = OT.conf[:locales]
        self[:support_host] = site.dig(:support, :host) # defaults to nil
        self[:authentication] = site[:authentication]
        self[:description] = i18n[:COMMON][:description]
        self[:keywords] = i18n[:COMMON][:keywords]
        self[:ot_version] = OT::VERSION.inspect
        self[:ruby_version] = "#{OT.sysinfo.vm}-#{OT.sysinfo.ruby.join}"
        self[:authenticated] = authenticated
        self[:display_promo] = false
        self[:display_feedback] = true
        self[:feedback_text] = i18n[:COMMON][:feedback_text]
        self[:frontend_host] = frontend_host
        self[:frontend_development] = frontend_development
        self[:no_cache] = false
        self[:display_sitenav] = true

        self[:jsvars] = []
        # Pass the authentication flag settings to the frontends.
        self[:jsvars] << jsvar(:authentication, authentication)
        self[:jsvars] << jsvar(:shrimp, sess.add_shrimp) if sess

        if authenticated && cust
          self[:colonel] = cust.role?(:colonel)
          self[:metadata_record_count] = cust.metadata_list.length
          self[:jsvars] << jsvar(:metadata_record_count, self[:metadata_record_count])

          self[:domains_enabled] = domains[:enabled] || false  # only for authenticated
          self[:jsvars] << jsvar(:domains_enabled, self[:domains_enabled])

          self[:jsvars] << jsvar(:custid, cust.custid)
          self[:jsvars] << jsvar(:cust, cust.safe_dump)
          self[:jsvars] << jsvar(:email, cust.email)

          # TODO: We can remove this after we update the Account view to use
          # the value of cust.created to calculate the customer_since value
          # on-the-fly and in the time zone of the user.
          self[:jsvars] << jsvar(:customer_since, epochdom(cust.created))

          # There's no custom domain list when the feature is disabled.
          if self[:domains_enabled]
            self[:custom_domains_record_count] = cust.custom_domains.length
            self[:custom_domains] = cust.custom_domains_list.collect { |obj| obj.display_domain }.sort
            self[:jsvars] << jsvar(:custom_domains_record_count, self[:custom_domains_record_count])
            self[:jsvars] << jsvar(:custom_domains, self[:custom_domains])
          end
        end

        unless sess.nil?
          self[:gravatar_uri] = gravatar(cust.email) unless cust.anonymous?

          if cust.pending? && self.class != Onetime::App::Views::Shared
            add_message i18n[:COMMON][:verification_sent_to] + " #{cust.custid}."
          else
            add_errors sess.get_error_messages
          end

          add_messages sess.get_info_messages
          add_form_fields sess.get_form_fields!
        end

        # Link to the pricing page can be seen regardless of authentication status
        self[:plans_enabled] = site.dig(:plans, :enabled) || false
        self[:jsvars] << jsvar(:plans_enabled, self[:plans_enabled])

        self[:jsvars] << jsvar(:vue_component_name, self.vue_component_name)
        self[:jsvars] << jsvar(:locale, locale)
        self[:jsvars] << jsvar(:is_default_locale, is_default_locale)
        self[:jsvars] << jsvar(:supported_locales, self[:supported_locales])
        self[:jsvars] << jsvar(:frontend_host, frontend_host)
        self[:jsvars] << jsvar(:authenticated, authenticated)
        self[:jsvars] << jsvar(:site_host, site[:host])

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

        self[:display_links] = true
        self[:display_masthead] = true

        self[:subtitle] = "Onetime"

        self[:jsvars] << jsvar(:display_links, self[:display_links])
        self[:jsvars] << jsvar(:display_masthead, self[:display_masthead])

        @plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
        @plan ||= Onetime::Plan.plan('anonymous')
        @is_paid = plan.paid?

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

      def setup_plan_variables
        Onetime::Plan.plans.each_pair do |planid,plan|
          self[plan.planid] = {
            :price => plan.price.zero? ? 'Free' : plan.calculated_price,
            :original_price => plan.price.to_i,
            :ttl => plan.options[:ttl].in_days.to_i,
            :size => plan.options[:size].to_i,
            :api => plan.options[:api],
            :name => plan.options[:name],
            :dark_mode => plan.options[:dark_mode],
            :custom_domains => plan.options[:custom_domains],
            :email => plan.options[:email],
            :planid => planid
          }
          self[plan.planid][:price_adjustment] = (plan.calculated_price.to_i != plan.price.to_i)
        end

        @plans = [:basic, :identity, :dedicated]

        self[:default_plan] = self[@plans.first.to_s] || self['basic']

        self[:planid] = self[:default_plan][:planid]
      end

      def get_split_test_values testname
        varname = "#{testname}_group"
        if OT::SplitTest.test_running? testname
          group_idx = cust.get_persistent_value sess, varname
          if group_idx.nil?
            group_idx = OT::SplitTest.send(testname).register_visitor!
            OT.info "Split test visitor: #{sess.sessid} is in group #{group_idx}"
            cust.set_persistent_value sess, varname, group_idx
          end
          @plans = *OT::SplitTest.send(testname).sample!(group_idx.to_i)
        else
          @plans = yield # TODO: not tested
        end
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

      # Each page has exactly one #app element and each view can have its
      # own Vue component. This method allows setting the component name
      # that is created and mounted in main.ts. If not set, the component
      # name is derived from the view class name.
      attr_writer :vue_component_name
      def vue_component_name
        @vue_component_name || self.class.vue_component_name
      end

      class << self
        attr_accessor :pagename, :vue_component_name

        # Set the Vue component at the class level. Each view instance
        # can override this value with its own #vue_component_name method.
        attr_writer :vue_component_name
        def vue_component_name
          @vue_component_name || self.name.split('::').last
        end
      end

    end
  end
end
