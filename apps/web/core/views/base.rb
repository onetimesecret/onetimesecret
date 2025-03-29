# apps/web/core/views/base.rb

require 'chimera'

require 'onetime/middleware'

require 'v2/models/customer'

require_relative 'helpers'
require_relative 'serializers'
#
# - **Helpers**: Provide utility methods for internal use
# - **Serializers**: Transform internal state for frontend consumption
#
module Core
  module Views
    class BaseView < Chimera
      include Core::Views::HTMLTagsSerializer
      include Core::Views::I18nHelpers
      include Core::Views::ViteManifest
      include Core::Views::InitializeVarsHelpers
      include Onetime::TimeUtils

      self.template_path = './templates/web'
      self.template_extension = 'html'
      self.view_namespace = Core::Views
      self.view_path = './app/web/views'

      attr_accessor :req, :sess, :cust, :locale, :messages, :form_fields, :pagename
      attr_reader :global_vars, :i18n_instance

      attr_reader :plan, :is_paid, :canonical_domain, :display_domain, :domain_strategy
      attr_reader :domain_id, :domain_branding, :domain_logo, :custom_domain

      def initialize req, sess=nil, cust=nil, locale=nil, *args
        @req = req
        @sess = sess
        @cust = cust || V2::Customer.anonymous
        @locale = locale || (req.nil? ? OT.default_locale : req.env['ots.locale'])
        @messages = []

        # Use the refactored helper method
        @global_vars = initialize_vars(req, sess, cust, @locale)
        @i18n_instance = self.i18n

        # Run serializers and apply to view
        if self.class.serializers.any?
          serializer_data = SerializerRegistry.run(
            self.class.serializers,
            @vars,
            @i18n_instance
          )

          # Apply serialized data to view variables
          serializer_data.each do |key, value|
            self[key] = value
          end
        end

        init(*args) if respond_to?(:init)

        # Serialize the jsvars hash to JSON and this is the final window
        # object that will be passed to the frontend.
        self[:window] = self[:jsvars].to_json

          # self[:jsvars] = {}

          # Add the nonce to the jsvars hash if it exists. See `carefully`.
          # self[:nonce] = req.env.fetch('ots.nonce', nil)

          # # Add the global site banner if there is one
          # self[:jsvars][:global_banner] = jsvar(OT.global_banner) if OT.global_banner

          # # Add UI settings
          # self[:jsvars][:ui] = jsvar(interface[:ui])

          # Pass the authentication flag settings to the frontends.
          # self[:jsvars][:authentication] = jsvar(authentication) # nil is okay
          # self[:jsvars][:shrimp] = jsvar(sess.add_shrimp) if sess

          # # Only send the regions config when the feature is enabled.
          # self[:jsvars][:regions_enabled] = jsvar(regions_enabled)
          # self[:jsvars][:regions] = jsvar(regions) if regions_enabled

          # self[:jsvars][:domains_enabled] = jsvar(domains_enabled) # only for authenticated

          # if authenticated && cust
          #     # self[:jsvars][:custid] = jsvar(cust.custid)
          #     # self[:jsvars][:cust] = jsvar(cust.safe_dump)
          #     # self[:jsvars][:email] = jsvar(cust.email)

          #     # # TODO: We can remove this after we update the Account view to use
          #     # # the value of cust.created to calculate the customer_since value
          #     # # on-the-fly and in the time zone of the user.
          #     # self[:jsvars][:customer_since] = jsvar(epochdom(cust.created))

          #     # There's no custom domain list when the feature is disabled.
          #     # if domains_enabled
          #     #   custom_domains = cust.custom_domains_list.filter_map do |obj|
          #     #     # Only verified domains that resolve
          #     #     unless obj.ready?
          #     #       # For now just log until we can reliably re-attempt verification and
          #     #       # have some visibility which customers this will affect. We've made
          #     #       # the verification more stringent so currently many existing domains
          #     #       # would return obj.ready? == false.
          #     #       OT.li "[custom_domains] Allowing unverified domain: #{obj.display_domain} (#{obj.verified}/#{obj.resolving})"
          #     #     end

          #     #     obj.display_domain
          #     #   end
          #     #   self[:jsvars][:custom_domains] = jsvar(custom_domains.sort)
          #     # end
          # else
          #
          # Ensure that these keys are always present in jsvars, even if nil
          # NOTE TO SELF: this will be takeh car of by virtue of `self.output_template`
          # ensure_exist = [:domains_enabled, :custid, :cust, :email, :customer_since, :custom_domains]
          #   # We do this so that in our typescript we can assume either a value
          #   # or nil (null), avoiding undefined altogether.
          #   ensure_exist.each do |key|
          #     self[:jsvars][key] = jsvar(nil)
          #   end
          # end

          # # Link to the pricing page can be seen regardless of authentication status
          # self[:jsvars][:plans_enabled] = jsvar(site.dig(:plans, :enabled) || false)

          # Internationalization
          # self[:jsvars][:locale] = jsvar(display_locale) # the locale the user sees
          # self[:jsvars][:is_default_locale] = jsvar(is_default_locale)
          # self[:jsvars][:default_locale] = jsvar(OT.default_locale) # the application default
          # self[:jsvars][:fallback_locale] = jsvar(OT.fallback_locale)
          # self[:jsvars][:supported_locales] = jsvar(OT.supported_locales)
          # self[:jsvars][:i18n_enabled] = jsvar(OT.i18n_enabled)

          # # Diagnostics
          # sentry = OT.conf.dig(:diagnostics, :sentry) || {}
          # self[:jsvars][:d9s_enabled] = jsvar(OT.d9s_enabled) # pass global flag
          # Onetime.with_diagnostics do
          #   config = sentry.fetch(:frontend, {})
          #   self[:jsvars][:diagnostics] = {
          #     # e.g. {dsn: "https://...", ...}
          #     sentry: jsvar(config)
          #   }
          # end

          # self[:jsvars][:incoming_recipient] = jsvar(incoming_recipient)
          # self[:jsvars][:support_host] = jsvar(support_host)
          # self[:jsvars][:secret_options] = jsvar(secret_options)
          # self[:jsvars][:frontend_host] = jsvar(frontend_host)

          # self[:jsvars][:authenticated] = jsvar(authenticated)

          # self[:jsvars][:site_host] = jsvar(site[:host])

          # self[:jsvars][:canonical_domain] = jsvar(canonical_domain)
          # self[:jsvars][:domain_strategy] = jsvar(domain_strategy)
          # self[:jsvars][:domain_id] = jsvar(domain_id)
          # self[:jsvars][:domain_branding] = jsvar(domain_branding)
          # self[:jsvars][:domain_logo] = jsvar(domain_logo)
          # self[:jsvars][:display_domain] = jsvar(display_domain)

          # self[:jsvars][:ot_version] = jsvar(OT::VERSION.inspect)
          # self[:jsvars][:ruby_version] = jsvar("#{OT.sysinfo.vm}-#{OT.sysinfo.ruby.join}")

          # self[:jsvars][:messages] = jsvar(self[:messages])

          # plans = Onetime::Plan.plans.transform_values do |plan|
          #   plan.safe_dump
          # end
          # self[:jsvars][:available_plans] = jsvar(plans)

          # @plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
          # @plan ||= Onetime::Plan.plan('anonymous')
          # @is_paid = plan.paid?

          # self[:jsvars][:plan] = jsvar(plan.safe_dump)
          # self[:jsvars][:is_paid] = jsvar(@is_paid)
          # self[:jsvars][:default_planid] = jsvar('basic')

        # init(*args) if respond_to? :init
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
        # pagename is used in the i18n[:web][:pagename] hash which (if present)
        # provides the locale strings specifically for this view. For that to
        # work, the view being used has a matching name in the locales file.
        def pagename
          # NOTE: There's some speculation that setting a class instance variable
          # inside the class method could present a race condition in between the
          # check for nil and running the expression to set it. It's possible but
          # every thread will produce the same result. Winning by technicality is
          # one thing but the reality of software development is another. Process
          # is more important than clever design. Instead, a safer practice is to
          # set the class instance variable here in the class definition.
          @pagename ||= self.name.split('::').last.downcase.to_sym
        end

        # Class-level serializers list
        def serializers
          @serializers ||= []
        end

        # Add serializers to this view
        def use_serializers(*serializer_list)
          serializer_list.each do |serializer|
            serializers << serializer unless serializers.include?(serializer)
          end
        end
      end

    end
  end
end
