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
  module Views
  end
  require 'onetime/app/web/views/helpers'
  class View < Mustache
    include Onetime::Views::Helpers
    self.template_path = './templates/web'
    self.view_namespace = Onetime::Views
    self.view_path = './app/web/views'
    attr_reader :req
    attr_accessor :sess, :cust, :messages, :form_fields
    def initialize req=nil, sess=nil, cust=nil, *args
      @req, @sess, @cust = req, sess, cust
      @messages = { :info => [], :error => [] }
      self[:subtitle] = "One Time"
      self[:monitored_link] = false
      self[:description] = "Keep sensitive information out of your chat logs and email. Share a secret link that is available only one time."
      self[:keywords] = "secret,password generator,share a secret,onetime"
      self[:ot_version] = OT::VERSION
      self[:authenticated] = sess.authenticated? if sess
      self[:people_we_care_about] = true
      self[:display_promo] = false
      
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
      
      if req && req.params[:errno] && Onetime::ERRNO.has_key?(req.params[:errno])
        add_error Onetime::ERRNO[req.params[:errno]]
      else
        unless sess.nil?
          add_error sess.error_message!
          add_form_fields sess.get_form_fields!
        end
      end
      init *args if respond_to? :init
    end
    def add_error msg
      messages[:error] << msg unless msg.to_s.empty?
    end
    def add_form_fields hsh
      (self.form_fields ||= {}).merge! hsh unless hsh.nil?
      unless form_fields
      end
    end
  end
  
  module Views
    class Homepage < Onetime::View
      def init *args
        self[:title] = "Share a secret"
        self[:monitored_link] = true
        self[:with_anal] = true
      end
    end
    module Info
      class Privacy < Onetime::View
        def init *args
          self[:title] = "Privacy Policy"
          self[:monitored_link] = true
          self[:with_anal] = true
        end
      end
       class Security < Onetime::View
        def init *args
          self[:title] = "Security Policy"
          self[:monitored_link] = true
          self[:with_anal] = true
        end
      end
    end
    class UnknownSecret < Onetime::View
      def init 
        self[:title] = "No such secret"
      end
    end
    class Shared < Onetime::View
      def init 
        self[:title] = "You received a secret"
        self[:body_class] = :generate
      end
      def display_lines
        ret = self[:secret_value].to_s.scan(/\n/).size + 2
        ret = ret > 20 ? 20 : ret
      end
      def one_liner
        self[:secret_value].to_s.scan(/\n/).size.zero?
      end
    end
    class Private < Onetime::View
      def init metadata
        self[:title] = "You saved a secret"
        self[:body_class] = :generate
        self[:metadata_key] = metadata.key
        self[:been_shared] = metadata.state?(:shared)
        self[:shared_date] = natural_time(metadata.shared.to_i || 0)
        secret = metadata.load_secret
        unless secret.nil?
          self[:secret_key] = secret.key
          self[:show_passphrase] = !secret.passphrase_temp.to_s.empty?
          self[:passphrase_temp] = secret.passphrase_temp
          self[:secret_value] = secret.can_decrypt? ? secret.decrypted_value : secret.value
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
    class Login < Onetime::View
      def init 
        self[:title] = "Login"
        self[:body_class] = :login
        self[:with_anal] = true
      end
    end
    class Signup < Onetime::View
      def init 
        self[:title] = "Create an account"
        self[:body_class] = :signup
        self[:with_anal] = true
        self[:planid] = req.params[:planid] if OT::Plan.plan?(req.params[:planid])
      end
    end
    class Pricing < Onetime::View
      def init 
        self[:title] = "Pricing Plans"
        self[:body_class] = :pricing
        self[:with_anal] = true
        Onetime::Plan.plans.each_pair do |planid,plan|
          self[planid] = {
            :price => plan.price.zero? ? 'Free' : plan.calculated_price,
            :original_price => plan.price.to_i,
            :ttl => plan.options[:ttl].in_days.to_i,
            :size => plan.options[:size].to_bytes.to_i,
            :api => plan.options[:api] ? 'Yes' : 'No'
          }
        end
      end
    end
    class Dashboard < Onetime::View
      def init 
        self[:title] = "Your Dashboard"
        self[:body_class] = :dashboard
        self[:with_anal] = true
        self[:metadata] = cust.metadata.collect { |m| 
          { :uri => private_uri(m), 
            :stamp => natural_time(m.updated), 
            :key => m.key,
            :been_shared => m.state?(:shared) }
        }
      end
    end
    class Account < Onetime::View
      def init 
        self[:title] = "Your Account"
        self[:body_class] = :account
        self[:with_anal] = true
        self[:price] = Onetime::Plan.plans[cust.planid].to_i
      end
    end
    class Error < Onetime::View
      def init *args
        self[:title] = "Oh cripes!"
      end
    end
  end
  
end
