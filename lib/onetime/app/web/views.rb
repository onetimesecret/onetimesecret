require 'mustache'
class Mustache
  def self.partial(name)
    path = "#{template_path}/#{name}.#{template_extension}"
    if Otto.env?(:dev)
      File.read(path)
    else
      @_partial_cache ||= {}
      @_partial_cache[path] ||= File.read(path)
      @_partial_cache[path]
    end
  end
end

module Onetime
  class App
    module Views
    end
    require 'onetime/app/web/views/helpers'
    class View < Mustache
      include Onetime::App::Views::Helpers
      self.template_path = './templates/web'
      self.view_namespace = Onetime::App::Views
      self.view_path = './app/web/views'
      attr_reader :req, :plan, :is_paid
      attr_accessor :sess, :cust, :locale, :messages, :form_fields
      def initialize req=nil, sess=nil, cust=nil, locale=nil, *args
        @req, @sess, @cust, @locale = req, sess, cust, locale
        @locale ||= req.env['ots.locale'] || OT.conf[:locales].first.to_s || 'en'
        @messages = { :info => [], :error => [] }
        self[:js], self[:css] = [], []
        self[:is_default_locale] = OT.conf[:locales].first.to_s == locale
        self[:supported_locales] = OT.conf[:locales]
        self[:unsupported_locales] = OT.conf[:unsupported_locales]
        self[:monitored_link] = false
        self[:description] = i18n[:COMMON][:description]
        self[:keywords] = i18n[:COMMON][:keywords]
        self[:ot_version] = OT::VERSION.inspect
        self[:ot_version_id] = self[:ot_version].gibbler.short
        self[:authenticated] = sess.authenticated? if sess
        self[:display_promo] = false
        self[:display_feedback] = true
        self[:colonel] = cust.role?(:colonel) if cust
        self[:feedback_text] = OT.conf[:text][:feedback]
        self[:nonpaid_recipient_text] = OT.conf[:text][:nonpaid_recipient_text]
        self[:paid_recipient_text] = OT.conf[:text][:paid_recipient_text]
        self[:base_domain] = OT.conf[:site][:domain]
        self[:is_subdomain] = ! req.env['ots.subdomain'].nil?
        self[:no_cache] = false
        self[:display_sitenav] = true
        self[:jsvars] = []
        self[:jsvars] << jsvar(:shrimp, sess.add_shrimp) if sess
        self[:jsvars] << jsvar(:custid, cust.custid)
        self[:jsvars] << jsvar(:email, cust.email)
        self[:display_links] = true
        self[:display_options] = true# sess.authenticated?
        self[:display_recipients] = sess.authenticated?
        self[:display_masthead] = true
        if self[:is_subdomain]
          tmp = req.env['ots.subdomain']
          self[:subdomain] = tmp.to_hash
          self[:subdomain]['company_domain'] = tmp.company_domain || 'One-Time Secret'
          self[:subdomain]['company'] = "One-Time Secret"
          self[:subtitle] = self[:subdomain]['company'] || self[:subdomain]['company_domain']
          self[:display_feedback] = sess.authenticated?
          self[:display_icons] = sess.authenticated?
          self[:display_faq] = false
          self[:actionable_visitor] = sess.authenticated?
          self[:override_styles] = true
          self[:primary_color] = req.env['ots.subdomain'].primary_color
          self[:secondary_color] = req.env['ots.subdomain'].secondary_color
          self[:border_color] = req.env['ots.subdomain'].border_color
          self[:banner_url] = req.env['ots.subdomain'].logo_uri
          self[:display_otslogo] = self[:banner_url].to_s.empty?
          self[:with_broadcast] = false
        else
          self[:subtitle] = "One Time"
          self[:display_faq] = true
          self[:display_icons] = true
          self[:display_otslogo] = true
          self[:actionable_visitor] = true
          # NOTE: uncomment the following line to show the broadcast
          #self[:with_broadcast] = ! self[:authenticated]
        end
        unless sess.nil?
          self[:gravatar_uri] = gravatar(cust.email) unless cust.anonymous?
          if sess.referrer
            self[:via_hn] = !sess.referrer.match(/news.ycombinator.com/).nil?
            self[:via_reddit] = !sess.referrer.match(/www.reddit.com/).nil?
            self[:via_test] = !sess.referrer.match(/ot.com/).nil?
          end
          if cust.has_key?(:verified) && cust.verified.to_s != 'true' && self.class != Onetime::App::Views::Shared
            add_message i18n[:COMMON][:verification_sent_to] + " #{cust.custid}."
          else
            add_error sess.error_message!
          end
          add_message sess.info_message!
          add_form_fields sess.get_form_fields!
        end
        @plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
        @plan ||= Onetime::Plan.plan('anonymous')
        @is_paid = plan.paid?
        init *args if respond_to? :init
      end
      def i18n
        pagename = self.class.name.split('::').last.downcase.to_sym
        @i18n ||= {
          locale: self.locale,
          default: OT.conf[:locales].first.to_s,
          page: OT.locales[self.locale][:web][pagename],
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
            :api => plan.options[:api] ? 'Yes' : 'No',
            :name => plan.options[:name],
            :planid => planid
          }
          self[plan.planid][:price_adjustment] = (plan.calculated_price.to_i != plan.price.to_i)
        end
        @plans = if self[:via_test] || self[:via_hn]
          [:personal_hn, :professional_v1, :agency_v1]
        elsif self[:via_reddit]
          [:personal_reddit, :professional_v1, :agency_v1]
        else
          [:individual_v1, :professional_v1, :agency_v1]
        end
        unless cust.anonymous?
          plan_idx = case cust.planid
          when /personal/
            0
          when /professional/
            1
          when /agency/
            2
          end
          @plans[plan_idx] = cust.planid unless plan_idx.nil?
        end
        self[:default_plan] = self[@plans.first.to_s] || self['individual_v1']
        OT.ld self[:default_plan].to_json
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
        messages[:info] << msg unless msg.to_s.empty?
      end
      def add_error msg
        messages[:error] << msg unless msg.to_s.empty?
      end
      def add_form_fields hsh
        (self.form_fields ||= {}).merge! hsh unless hsh.nil?
      end
    end

    module Views
      module CreateSecretElements
        def default_expiration
          option_count = expiration_options.size
          self[:authenticated] ? (option_count)/2 : option_count-1
        end
        def expiration_options
          if @expiration_options.nil?
            selected = (!sess || !sess.authenticated?) ? 7.days : 7.days
            disabled = (!sess || !sess.authenticated?) ? 7.days : plan.options[:ttl]
            @expiration_options = [
              [5.minutes, "5 minutes"],
              [30.minutes, "30 minutes"],
              [1.hour, "1 hour"],
              [4.hour, "4 hours"],
              [12.hour, "12 hours"],
              [1.days, "1 day"],
              [2.days, "2 days"],
              [7.days, "7 days"],
            ]
            if self[:authenticated]
              @expiration_options << [14.days, "14 days"] if plan.options[:ttl] >= 14.days
              @expiration_options << [30.days, "30 days"] if plan.options[:ttl] >= 30.days
              if plan.options[:ttl] > 30.days
                @expiration_options.push *[
                  [60.days, "2 months"],
                  [90.days, "3 months"]
                ]
              end
            end
          end
          @expiration_options
        end
      end
      class Homepage < Onetime::App::View
        include CreateSecretElements
        def init *args
          self[:title] = "Share a secret"
          self[:monitored_link] = !self[:is_subdomain]
          self[:with_analytics] = true
        end
      end
      class Incoming < Onetime::App::View
        include CreateSecretElements
        def init *args
          self[:title] = "Share a secret"
          self[:monitored_link] = !self[:is_subdomain]
          self[:with_analytics] = true
          self[:incoming_recipient] = OT.conf[:incoming][:email]
          self[:display_feedback] = self[:display_icons] = false
          self[:display_masthead] = self[:display_links] = false
        end
      end
      module Docs
        class Api < Onetime::App::View
          def init *args
            self[:title] = "API Docs"
            self[:subtitle] = "OTS Developers"
            self[:monitored_link] = !self[:is_subdomain]
            self[:with_analytics] = true
            self[:css] << '/css/docs.css'
          end
          def baseuri_httpauth
            scheme = Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
            [scheme, 'USERNAME:APITOKEN@', Onetime.conf[:site][:host]].join
          end
        end
        class Api < Onetime::App::View
          class Secrets < Api
          end
          class Libs < Api
          end
        end
      end
      module Info
        class Privacy < Onetime::App::View
          def init *args
            self[:title] = "Privacy Policy"
            self[:monitored_link] = true
            self[:with_analytics] = true
          end
        end
         class Security < Onetime::App::View
          def init *args
            self[:title] = "Security Policy"
            self[:monitored_link] = true
            self[:with_analytics] = true
          end
        end
        class Terms < Onetime::App::View
          def init *args
            self[:title] = "Terms and Conditions"
            self[:monitored_link] = true
            self[:with_analytics] = true
          end
        end
      end
      class UnknownSecret < Onetime::App::View
        def init
          self[:title] = "No such secret"
          self[:display_feedback] = false
        end
      end
      class Shared < Onetime::App::View
        def init
          self[:title] = "You received a secret"
          self[:body_class] = :generate
          self[:display_feedback] = false
          self[:display_sitenav] = false
          self[:display_links] = false
          self[:display_icons] = false
          self[:monitored_link] = false
          self[:display_masthead] = false
          self[:no_cache] = true
        end
        def display_lines
          v = self[:secret_value].to_s
          ret = ((80+v.size)/80) + (v.scan(/\n/).size) + 3
          ret = ret > 30 ? 30 : ret
        end
        def one_liner
          v = self[:secret_value].to_s
          v.scan(/\n/).size.zero?
        end
      end
      class Private < Onetime::App::View
        def init metadata
          self[:title] = "You saved a secret"
          self[:body_class] = :generate
          self[:metadata_key] = metadata.key
          self[:metadata_shortkey] = metadata.shortkey
          self[:secret_key] = metadata.secret_key
          self[:secret_shortkey] = metadata.secret_shortkey
          self[:recipients] = metadata.recipients
          self[:display_feedback] = false
          self[:no_cache] = true
          ttl = metadata.ttl.to_i  # the real ttl is always a whole number
          self[:created_date_utc] = epochformat(metadata.created.to_i)
          self[:expiration_stamp] = if ttl <= 1.minute
            '%d seconds' % ttl
          elsif ttl <= 1.hour
            '%d minutes' % ttl.in_minutes
          elsif ttl <= 1.day
            '%d hours' % ttl.in_hours
          else
            '%d days' % ttl.in_days
          end
          secret = metadata.load_secret
          if secret.nil?
            self[:is_received] = metadata.state?(:received)
            self[:is_burned] = metadata.state?(:burned)
            self[:is_destroyed] = self[:is_burned] || self[:is_received]
            self[:received_date] = natural_time(metadata.received.to_i || 0)
            self[:received_date_utc] = epochformat(metadata.received.to_i || 0)
            self[:burned_date] = natural_time(   metadata.burned.to_i || 0)
            self[:burned_date_utc] = epochformat(metadata.burned.to_i || 0)
          else
            self[:maxviews] = secret.maxviews
            self[:has_maxviews] = true if self[:maxviews] > 1
            self[:view_count] = secret.view_count
            if secret.viewable?
              self[:has_passphrase] = !secret.passphrase.to_s.empty?
              self[:can_decrypt] = secret.can_decrypt?
              self[:secret_value] = secret.decrypted_value if self[:can_decrypt]
              self[:truncated] = secret.truncated
            end
          end
          self[:show_secret] = !secret.nil? && !(metadata.state?(:viewed) || metadata.state?(:received) || metadata.state?(:burned))
          self[:show_secret_link] = !(metadata.state?(:received) || metadata.state?(:burned)) && (self[:show_secret] || metadata.owner?(cust)) && self[:recipients].nil?
          self[:show_metadata_link] = metadata.state?(:new)
          self[:show_metadata] = !metadata.state?(:viewed) || metadata.owner?(cust)
        end
        def share_uri
          [baseuri, :secret, self[:secret_key]].join('/')
        end
        def metadata_uri
          [baseuri, :private, self[:metadata_key]].join('/')
        end
        def burn_uri
          [baseuri, :private, self[:metadata_key], 'burn'].join('/')
        end
        def display_lines
          ret = self[:secret_value].to_s.scan(/\n/).size + 2
          ret = ret > 20 ? 20 : ret
        end
        def one_liner
          self[:secret_value].to_s.scan(/\n/).size.zero?
        end
      end
      class Burn < Onetime::App::View
        def init metadata
          self[:title] = "You saved a secret"
          self[:body_class] = :generate
          self[:metadata_key] = metadata.key
          self[:metadata_shortkey] = metadata.shortkey
          self[:secret_key] = metadata.secret_key
          self[:secret_shortkey] = metadata.secret_shortkey
          self[:state] = metadata.state
          self[:recipients] = metadata.recipients
          self[:display_feedback] = false
          self[:no_cache] = true
          self[:show_metadata] = !metadata.state?(:viewed) || metadata.owner?(cust)
          secret = metadata.load_secret
          ttl = metadata.ttl.to_i  # the real ttl is always a whole number
          self[:expiration_stamp] = if ttl <= 1.minute
            '%d seconds' % ttl
          elsif ttl <= 1.hour
            '%d minutes' % ttl.in_minutes
          elsif ttl <= 1.day
            '%d hours' % ttl.in_hours
          else
            '%d days' % ttl.in_days
          end
          if secret.nil?
            self[:is_received] = metadata.state?(:received)
            self[:is_burned] = metadata.state?(:burned)
            self[:is_destroyed] = self[:is_burned] || self[:is_received]
            self[:received_date] = natural_time(metadata.received.to_i || 0)
            self[:received_date_utc] = epochformat(metadata.received.to_i || 0)
            self[:burned_date] = natural_time(   metadata.burned.to_i || 0)
            self[:burned_date_utc] = epochformat(metadata.burned.to_i || 0)
          else
            if secret.viewable?
              self[:has_passphrase] = !secret.passphrase.to_s.empty?
              self[:can_decrypt] = secret.can_decrypt?
              self[:secret_value] = secret.decrypted_value if self[:can_decrypt]
              self[:truncated] = secret.truncated
            end
          end
        end
        def metadata_uri
          [baseuri, :private, self[:metadata_key]].join('/')
        end
      end
      class Forgot < Onetime::App::View
        def init
          self[:title] = "Forgotten Password"
          self[:body_class] = :login
          self[:monitored_link] = true
          self[:with_analytics] = true
        end
      end
      class Login < Onetime::App::View
        def init
          self[:title] = "Login"
          self[:body_class] = :login
          self[:monitored_link] = true
          self[:with_analytics] = true
          if req.params[:custid]
            add_form_fields :custid => req.params[:custid]
          end
          if sess.authenticated?
            add_message "You are already logged in."
          end
        end
      end
      class Signup < Onetime::App::View
        def init
          self[:title] = "Create an account"
          self[:body_class] = :signup
          self[:monitored_link] = true
          self[:with_analytics] = true
          if OT::Plan.plan?(req.params[:planid])
            self[:planid] = req.params[:planid]
            plan = OT::Plan.plan(req.params[:planid])
            self[:plan] = {
              :price => plan.price.zero? ? 'Free' : plan.calculated_price,
              :original_price => plan.price.to_i,
              :ttl => plan.options[:ttl].in_days.to_i,
              :size => plan.options[:size].to_bytes.to_i,
              :api => plan.options[:api].to_s == 'true',
              :name => plan.options[:name],
              :private => plan.options[:private].to_s == 'true',
              :cname => plan.options[:cname].to_s == 'true',
              :is_paid => plan.paid?,
              :planid => req.params[:planid]
            }
          else
            add_error "Unknown plan"
          end
        end
      end
      class Plans < Onetime::App::View
        def init
          self[:title] = "Create an Account"
          self[:body_class] = :pricing
          self[:monitored_link] = true
          self[:with_analytics] = true
          setup_plan_variables
        end
        def plan1;  self[@plans[0].to_s]; end
        def plan2;  self[@plans[1].to_s]; end
        def plan3;  self[@plans[2].to_s]; end
        def plan4;  self[@plans[3].to_s]; end
      end
      class Dashboard < Onetime::App::View
        include CreateSecretElements
        def init
          self[:title] = "Your Dashboard"
          self[:body_class] = :dashboard
          self[:monitored_link] = true
          self[:with_analytics] = false
          self[:metadata] = cust.metadata.collect do |m|
            { :uri => private_uri(m),
              :stamp => natural_time(m.updated),
              :updated => epochformat(m.updated),
              :key => m.key,
              :shortkey => m.key.slice(0,8),
              # Backwards compatible for metadata created prior to Dec 5th, 2014 (14 days)
              :secret_shortkey => m.secret_shortkey.to_s.empty? ? nil : m.secret_shortkey,
              :recipients => m.recipients,
              :is_received => m.state?(:received),
              :is_burned => m.state?(:burned),
              :is_destroyed => (m.state?(:received) || m.state?(:burned))}
          end.compact
          self[:received],self[:notreceived] =
            *self[:metadata].partition{ |m| m[:is_destroyed] }
          self[:received].sort!{ |a,b| b[:updated] <=> a[:updated] }
          self[:has_secrets] = !self[:metadata].empty?
          self[:has_received] = !self[:received].empty?
          self[:has_notreceived] = !self[:notreceived].empty?
        end
      end
      class Account < Onetime::App::View
        def init
          self[:title] = "Your Account"
          self[:body_class] = :account
          self[:monitored_link] = true
          self[:with_analytics] = true
          self[:price] = plan.calculated_price
          self[:is_paid] = plan.paid?
          self[:customer_since] = epochdom(cust.created)
          self[:contributor] = cust.contributor?
          if self[:contributor]
            self[:contributor_since] = epochdate(cust.contributor_at)
          end
          self[:has_cname] = cust.has_key?(:cname)
          self[:cname] = cust.cname || 'yourcompany'
          self[:cust_subdomain] = cust.load_subdomain
          self[:cname_uri] = '//%s.%s' % [self[:cname], self[:base_domain]]
          self[:cname_uri] << (':%d' % req.env['SERVER_PORT']) if ![443, 80].member?(req.env['SERVER_PORT'].to_i)
          if self[:colonel]
            if cust.passgen_token.nil?
              cust.update_passgen_token sess.sessid.gibbler
            end
            self[:token] = cust.passgen_token
            self[:js] << '/etc/packer/base2.js'
            self[:js] << '/etc/packer/packer.js'
            self[:js] << '/etc/packer/words.js'
          end
        end
      end
      class Error < Onetime::App::View
        def init *args
          self[:title] = "Oh cripes!"
        end
      end
      class About < Onetime::App::View
        def init *args
          self[:title] = "About Us"
          self[:body_class] = :info
          self[:monitored_link] = true
          self[:with_analytics] = true
          setup_plan_variables
        end
      end
      class Translations < Onetime::App::View
        def init *args
          self[:title] = "Help us translate"
          self[:body_class] = :info
          self[:monitored_link] = true
          self[:with_analytics] = true
        end
      end
      class Logo < Onetime::App::View
        def init *args
          self[:title] = "Contest: Help us get a logo"
          self[:body_class] = :info
          self[:monitored_link] = true
          self[:with_analytics] = true
          self[:with_broadcast] = false
        end
      end
      class NotFound < Onetime::App::View
        def init *args
          self[:title] = "Page not found"
          self[:body_class] = :info
          self[:monitored_link] = true
          self[:with_analytics] = true
        end
      end
      class Feedback < Onetime::App::View
        def init *args
          self[:title] = "Your Feedback"
          self[:body_class] = :info
          self[:monitored_link] = true
          self[:with_analytics] = true
          self[:display_feedback] = false
          #self[:popular_feedback] = OT::Feedback.popular.collect do |k,v|
          #  {:msg => k, :stamp => natural_time(v) }
          #end
        end
      end
      class Contributor < Onetime::App::View
        attr_accessor :secret
        def init *args
          self[:title] = "Contribute"
          self[:contributor] = cust.contributor?
          if self[:contributor]
            self[:contributor_since] = epochdate(cust.contributor_at)
          end
        end
      end
    end
  end

end
