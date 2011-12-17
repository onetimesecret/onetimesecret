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
      attr_accessor :sess, :cust, :messages, :form_fields
      def initialize req=nil, sess=nil, cust=nil, *args
        @req, @sess, @cust = req, sess, cust
        @messages = { :info => [], :error => [] }
        self[:js] = []
        self[:subtitle] = "One Time"
        self[:monitored_link] = false
        self[:description] = "Keep sensitive information out of your chat logs and email. Share a secret link that is available only one time."
        self[:keywords] = "secret,password generator,share a secret,onetime"
        self[:ot_version] = OT::VERSION.inspect
        self[:authenticated] = sess.authenticated? if sess
        self[:people_we_care_about] = true
        self[:display_promo] = false
        self[:display_feedback] = true
        self[:colonel] = cust.role?(:colonel) if cust
        self[:feedback_text] = OT.conf[:text][:feedback]
        self[:recipient_text] = OT.conf[:text][:recipient]
        if Onetime.conf[:site][:cobranded]
          self[:display_faq] = false
          self[:override_styles] = true
          self[:display_otslogo] = false
          self[:primary_color] = Onetime.conf[:site][:primary_color] 
          self[:secondary_color] = Onetime.conf[:site][:secondary_color] 
          self[:border_color] = Onetime.conf[:site][:border_color] 
          self[:banner_url] = Onetime.conf[:site][:banner_url] 
        else
          self[:display_faq] = true
          self[:display_otslogo] = true
        end
        unless sess.nil?
          if sess.referrer
            self[:via_hn] = !sess.referrer.match(/news.ycombinator.com/).nil?
            self[:via_reddit] = !sess.referrer.match(/www.reddit.com/).nil?
            self[:via_test] = !sess.referrer.match(/www.ot.com/).nil?
          end
          if cust.has_key?(:verified) && cust.verified.to_s != 'true' && self.class != Onetime::App::Views::Shared
            add_message "A verification was sent to #{cust.custid}."
          else
            add_error sess.error_message!
          end
          add_message sess.info_message!
          add_form_fields sess.get_form_fields!
        end
        @plan = Onetime::Plan.plans[cust.planid] unless cust.nil?
        @plan ||= Onetime::Plan.plans['anonymous']
        @is_paid = !plan.calculated_price.zero?
        init *args if respond_to? :init
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
        unless form_fields
        end
      end
      def expiration_options
        selected = (!sess || !sess.authenticated?) ? 2.days : 7.days
        disabled = (!sess || !sess.authenticated?) ? 2.days : plan.options[:ttl]
        options = [
          [1.hour, "1 hour"],
          [4.hour, "4 hours"],
          [12.hour, "12 hours"],
          [1.days, "1 day"],
          [2.days, "2 days"],
          [7.days, "7 days"],
          [14.days, "14 days"],
          [30.days, "30 days"],
          [60.days, "2 months"],
          [90.days, "3 months"]
        ]
        options.collect do |option|
          { 
            :value => option[0].to_i, 
            :text => option[1], 
            :selected => option[0] == selected,
            :disabled => option[0] > disabled
          }
        end
      end
    end
  
    module Views
      class Homepage < Onetime::App::View
        def init *args
          self[:title] = "Share a secret"
          self[:monitored_link] = true
          self[:with_analytics] = true
        end
      end
      module Docs
        class Api < Onetime::App::View
          def init *args
            self[:title] = "API Docs"
            self[:monitored_link] = true
            self[:with_analytics] = true
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
        end
      end
      class Shared < Onetime::App::View
        def init 
          self[:title] = "You received a secret"
          self[:body_class] = :generate
          self[:display_feedback] = false
        end
        def display_lines
          v = self[:secret_value].to_s
          ret = ((80+v.size)/80) + (v.scan(/\n/).size)
          ret = ret > 30 ? 30 : ret
        end
        def one_liner
          self[:secret_value].to_s.scan(/\n/).size.zero?
        end
      end
      class Private < Onetime::App::View
        def init metadata
          self[:title] = "You saved a secret"
          self[:body_class] = :generate
          self[:metadata_key] = metadata.key
          self[:been_shared] = metadata.state?(:shared)
          self[:shared_date] = natural_time(metadata.shared.to_i || 0)
          self[:display_feedback] = false
          ttl = metadata.ttl.to_i
          self[:expiration_stamp] = if ttl <= 1.hour
            '%d minutes' % ttl.in_minutes
          elsif ttl <= 1.day
            '%d hours' % ttl.in_hours
          else
            '%d days' % ttl.in_days
          end
          secret = metadata.load_secret
          unless secret.nil?
            self[:secret_key] = secret.key
            self[:show_passphrase] = !secret.passphrase_temp.to_s.empty?
            self[:passphrase_temp] = secret.passphrase_temp
            self[:secret_value] = secret.decrypted_value if secret.can_decrypt?
            self[:can_decrypt] = secret.can_decrypt?
            self[:truncated] = secret.truncated
          end
        end
        def share_uri
          [baseuri, :secret, self[:secret_key]].join('/')
        end
        def admin_uri
          [baseuri, :private, self[:metadata_key]].join('/')
        end
        def display_lines
          ret = self[:secret_value].to_s.scan(/\n/).size + 2
          ret = ret > 20 ? 20 : ret
        end
        def one_liner
          self[:secret_value].to_s.scan(/\n/).size.zero?
        end
      end
      class Login < Onetime::App::View
        def init 
          self[:title] = "Login"
          self[:body_class] = :login
          self[:monitored_link] = true
          self[:with_analytics] = true
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
            plan = OT::Plan.plans[req.params[:planid]]
            self[:plan] = {
              :price => plan.price.zero? ? 'Free' : plan.calculated_price,
              :original_price => plan.price.to_i,
              :ttl => plan.options[:ttl].in_days.to_i,
              :size => plan.options[:size].to_bytes.to_i,
              :api => plan.options[:api].to_s == 'true',
              :name => plan.options[:name],
              :private => plan.options[:private].to_s == 'true',
              :cname => plan.options[:cname].to_s == 'true',
              :is_paid => !plan.calculated_price.zero?,
              :planid => req.params[:planid]
            }
            if self[:plan][:is_paid]
              add_message "Good news! This plan is free until January 1st."
            end
          else
            add_error "Unknown plan"
          end
        end
      end
      class Pricing < Onetime::App::View
        def init 
          self[:title] = "Pricing Plans"
          self[:body_class] = :pricing
          self[:monitored_link] = true
          self[:with_analytics] = true
          Onetime::Plan.plans.each_pair do |planid,plan|
            self[planid.to_s] = {
              :price => plan.price.zero? ? 'Free' : plan.calculated_price,
              :original_price => plan.price.to_i,
              :ttl => plan.options[:ttl].in_days.to_i,
              :size => plan.options[:size].to_bytes.to_i,
              :api => plan.options[:api] ? 'Yes' : 'No',
              :name => plan.options[:name],
              :planid => planid
            }
            self[planid.to_s][:price_adjustment] = (plan.calculated_price.to_i != plan.price.to_i)
          end
          if self[:via_test] || self[:via_hn]
            @plans = [:anonymous, :personal_hn, :professional_v1, :agency_v1]
          elsif self[:via_reddit]
            @plans = [:anonymous, :personal_reddit, :professional_v1, :agency_v1]
          else
            @plans = get_split_test_values :initial_pricing do
              [:anonymous, :personal_v1, :professional_v1, :agency_v1]
            end
          end
          unless cust.anonymous?
            plan_idx = case cust.planid 
            when /personal/
              1
            when /professional/
              2
            when /agency/
              3
            end
            @plans[plan_idx] = cust.planid unless plan_idx.nil?
          end
        end
        def plan1;  self[@plans[0].to_s]; end
        def plan2;  self[@plans[1].to_s]; end
        def plan3;  self[@plans[2].to_s]; end
        def plan4;  self[@plans[3].to_s]; end
      end
      class Dashboard < Onetime::App::View
        def init 
          self[:title] = "Your Dashboard"
          self[:body_class] = :dashboard
          self[:monitored_link] = true
          self[:with_analytics] = true
          self[:metadata] = cust.metadata.collect do |m| 
            { :uri => private_uri(m), 
              :stamp => natural_time(m.updated), 
              :key => m.key,
              :been_shared => m.state?(:shared) }
          end.compact
          self[:has_secrets] = !self[:metadata].empty?
        end
      end
      class Account < Onetime::App::View
        def init 
          self[:title] = "Your Account"
          self[:body_class] = :account
          self[:monitored_link] = true
          self[:with_analytics] = true
          self[:price] = plan.calculated_price
          self[:is_paid] = !plan.calculated_price.zero?
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
        end
      end
      class PasswordGenerator < Onetime::App::View
        def init *args
          self[:title] = "Password Generator"
          self[:body_class] = :info
          self[:monitored_link] = true
          self[:with_analytics] = true
          self[:token] = sess.sessid.gibbler
          self[:js] << '/etc/packer/base2.js'
          self[:js] << '/etc/packer/packer.js'
          self[:js] << '/etc/packer/words.js'
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
    end
  end
  
end
