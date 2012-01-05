

module Onetime
  module Logic
    class Base
      unless defined?(Onetime::Logic::Base::MOBILE_REGEX)
        MOBILE_REGEX = /^\+?\d{9,16}$/
        EMAIL_REGEX = %r{^(?:[_a-z0-9-]+)(\.[_a-z0-9-]+)*@([a-z0-9-]+)(\.[a-zA-Z0-9\-\.]+)*(\.[a-z]{2,4})$}i
      end
      attr_reader :sess, :cust, :params, :processed_params, :plan
      def initialize(sess, cust, params=nil)
        @sess, @cust, @params = sess, cust, params
        @processed_params ||= {}
        process_params if respond_to?(:process_params) && @params
        process_generic_params if @params
      end
      protected
      
      # Generic params that can appear anywhere are processed here.
      # This is called in initialize AFTER process_params so that 
      # values set here don't overwrite values that already exist.
      def process_generic_params
        # remember to set with ||= 
      end
      def form_fields
        OT.ld "No form_fields method for #{self.class}"
        {}
      end
      def raise_form_error msg
        ex = OT::FormError.new 
        ex.message = msg
        ex.form_fields = form_fields
        raise ex
      end
      def plan
        @plan = Onetime::Plan.plan(cust.planid) unless cust.nil?
        @plan ||= Onetime::Plan.plan('anonymous')
      end
      def limit_action event
        return if plan.paid?
        sess.event_incr! event
      end
      def valid_email?(guess)
        !guess.to_s.match(EMAIL_REGEX).nil?
      end
      def valid_mobile?(guess)
        !guess.to_s.tr('-.','').match(MOBILE_REGEX).nil?
      end
    end
    
    class ReceiveFeedback < OT::Logic::Base
      attr_reader :msg
      def process_params
        @msg = params[:msg].to_s.slice(0, 999)
      end
      
      def raise_concerns
        limit_action :send_feedback
        if @msg.empty? || @msg =~ /#{Regexp.escape(OT.conf[:text][:feedback])}/
          raise_form_error "You can be more original than that!"
        end
      end
      
      def process
        @msg = "#{msg} [%s]" % [cust.anonymous? ? sess.ipaddress : cust.custid]
        OT::Feedback.add @msg
        sess.set_info_message "Message received. Send as much as you like!"
      end
    end
    
    class CreateAccount < OT::Logic::Base
      attr_reader :cust
      attr_reader :planid, :custid, :password, :password2
      def process_params
        @planid = params[:planid].to_s
        @custid = params[:custid].to_s.downcase
        @password = params[:password].to_s
        @password2 = params[:password2].to_s
      end
      def raise_concerns
        limit_action :create_account
        raise OT::FormError, "You're already signed up" if sess.authenticated?
        raise_form_error "Username not available" if OT::Customer.exists?(custid)
        raise_form_error "Is that a valid email address?"  unless valid_email?(custid)
        raise_form_error "Passwords do not match" unless password == password2
        raise_form_error "Password is too short" unless password.size >= 6
        raise_form_error "Unknown plan type" unless OT::Plan.plan?(planid)
      end
      def process
        @plan = OT::Plan.plan(planid)
        @cust = OT::Customer.create custid
        cust.update_passphrase password
        sess.update_fields :custid => cust.custid #, :authenticated => 'true'
        cust.update_fields :planid => @plan.planid, :verified => false
        metadata, secret = Onetime::Secret.spawn_pair cust.custid, [sess.external_identifier]
        msg = "Thanks for verifying your account. "
        msg << %Q{We got you a secret fortune cookie!\n\n"%s"} % OT::Utils.random_fortune
        secret.encrypt_value msg
        secret.verification = true
        secret.custid = cust.custid
        secret.save
        view = OT::Email::Welcome.new cust, secret
        view.deliver_email
        if OT.conf[:colonels].member?(cust.custid)
          cust.role = :colonel 
        else
          cust.role = :customer unless cust.role?(:customer)
        end
      end
      private
      def form_fields
        { :planid => planid, :custid => custid }
      end
    end

    class AuthenticateSession < OT::Logic::Base
      attr_reader :custid, :stay
      attr_reader :session_ttl
      def process_params
        @custid = params[:u].to_s.downcase
        @passwd = params[:p]
        @stay = params[:stay].to_s == "true"
        @session_ttl = (stay ? 30.days : 20.minutes).to_i
        if @custid.to_s.index(':as:')
          @colonelname, @custid = *@custid.downcase.split(':as:')
        else
          @custid = @custid.downcase if @custid
        end
        if @passwd.to_s.empty?
          @cust = nil
        elsif @colonelname && OT::Customer.exists?(@colonelname) && OT::Customer.exists?(@custid)
          OT.info "[login-as-attempt] #{@colonelname} as #{@custid} #{@sess.ipaddress}"
          potential = OT::Customer.load @colonelname
          @colonel = potential if potential.passphrase?(@passwd)
          @cust = OT::Customer.load @custid if @colonel.role?(:colonel)
          OT.info "[login-as-success] #{@colonelname} as #{@custid} #{@sess.ipaddress}"
        elsif (potential = OT::Customer.load(@custid))
          @cust = potential if potential.passphrase?(@passwd)
        end
      end
      
      def raise_concerns
        limit_action :authenticate_session
        if @cust.nil?
          @cust ||= OT::Customer.anonymous
          raise_form_error "Try again"
        end
      end

      def process
        if success?
          OT.info "[login-success] #{cust.custid} #{cust.role}"
          #TODO: sess = OT::Session.new @sess.ipaddress, @sess.agent, @cust.custid
          #sess.destroy!   # get rid of the unauthenticated session ID
          #sess = sess
          sess.update_fields :custid => cust.custid, :authenticated => 'true'
          sess.ttl = session_ttl if @stay
          sess.save
          cust.save
          if OT.conf[:colonels].member?(cust.custid)
            cust.role = :colonel 
          else
            cust.role = :customer unless cust.role?(:customer)
          end
        else
          raise_form_error "Try again"
        end
      end
      
      def success?
        !cust.nil? && !cust.anonymous? && (cust.passphrase?(@passwd) || @colonel.passphrase?(@passwd))
      end
      
      private
      def form_fields
        {:custid => custid}
      end
    end

    class DestroySession < OT::Logic::Base
      def process_params
      end
      def raise_concerns
        limit_action :destroy_session
      end
      def process
        sess.destroy!
      end
    end
    
    class Dashboard < OT::Logic::Base
      def process_params
      end
      def raise_concerns
        limit_action :dashboard
      end
      def process
      end
    end
    
    class ViewAccount < OT::Logic::Base
      def process_params
      end
      def raise_concerns
        limit_action :show_account
      end
      def process
      end
    end
    
    class ResetPasswordRequest < OT::Logic::Base
      attr_reader :custid
      def process_params
        @custid = params[:u].to_s.downcase
      end
      def raise_concerns
        #limit_action :update_account
        raise_form_error "Not a valid email address" unless valid_email?(@custid)
        raise_form_error "Not a valid email address" unless OT::Customer.exists?(@custid)
      end
      def process
        cust = OT::Customer.load @custid
        secret = OT::Secret.create @custid, [@custid]
        secret.ttl = 24.hours
        secret.verification = true
        view = OT::Email::PasswordRequest.new cust, secret
        ret = view.deliver_email
        if ret.code == 200
          sess.set_info_message "We sent instructions to #{cust.custid}"
        else
          sess.set_info_message "Couldn't send the notification. Let Chris know."
        end
      end
    end

    class ResetPassword < OT::Logic::Base
      attr_reader :secret
      def process_params
        @secret = OT::Secret.load params[:key].to_s
        @newp = params[:newp].to_s
        @newp2 = params[:newp2].to_s
      end
      def raise_concerns
        raise OT::MissingSecret if secret.nil?
        raise OT::MissingSecret if secret.custid.to_s == 'anon'
        limit_action :update_account
        raise_form_error "New passwords do not match" unless @newp == @newp2
        raise_form_error "New password is too short" unless @newp.size >= 6
        raise_form_error "New password cannot match current password" if @newp == @currentp
      end
      def process
        cust = secret.load_customer
        cust.update_passphrase @newp
        sess.set_info_message "Password changed"
        secret.destroy!
      end
    end
    
    class UpdateAccount < OT::Logic::Base
      attr_reader :modified
      def process_params
        @currentp = params[:currentp].to_s
        @newp = params[:newp].to_s
        @newp2 = params[:newp2].to_s
      end
      def raise_concerns
        @modified ||= []
        limit_action :update_account
        if ! @currentp.empty?
          raise_form_error "Current password does not match" unless cust.passphrase?(@currentp)
          raise_form_error "New passwords do not match" unless @newp == @newp2
          raise_form_error "New password is too short" unless @newp.size >= 6
          raise_form_error "New password cannot match current password" if @newp == @currentp
        end
      end
      def process
        if cust.passphrase?(@currentp) && @newp == @newp2
          cust.update_passphrase @newp
          @modified << :password
          sess.set_info_message "Password changed"
        end
        if modified.empty?
          sess.set_error_message "Nothing changed" 
        else
          cust.update_time!
        end
      end
      def modified? guess
        modified.member? guess
      end
    end

    class GenerateAPIkey < OT::Logic::Base
      attr_reader :apikey
      def process_params
      end
      def raise_concerns
        if (!sess.authenticated?) || (cust.anonymous?)
          raise_form_error "Sorry, we don't support that"
        end
      end
      def process
        unless cust.anonymous?
          @apikey = cust.regenerate_apitoken
        end
      end
    end
    
    class CreateSecret < OT::Logic::Base
      attr_reader :passphrase, :secret_value, :kind, :ttl, :recipient, :recipient_safe, :maxviews
      attr_reader :metadata, :secret
      def process_params
        @ttl = params[:ttl].to_i
        @ttl = 1.hour if @ttl < 1.hour
        @ttl = plan.options[:ttl] if @ttl > plan.options[:ttl]
        @maxviews = params[:maxviews].to_i
        @maxviews = 1 if @maxviews < 1
        @maxviews = (plan.options[:maxviews] || 100) if @maxviews > (plan.options[:maxviews] || 100)  # TODO
         if ['share', 'generate'].member?(params[:kind].to_s)
          @kind = params[:kind].to_s.to_sym 
        end
        @secret_value = kind == :share ? params[:secret] : Onetime::Utils.strand(12)
        @passphrase = params[:passphrase].to_s
        if plan.paid?
          params[:recipient] = [params[:recipient]].flatten.compact.uniq
          # TODO: enforce maximum number of recipients
          @recipient = params[:recipient].collect { |email_address| 
            next if email_address =~ /#{Regexp.escape(OT.conf[:text][:paid_recipient_text])}/
            unless valid_email?(email_address) #|| valid_mobile?(email_address)
              raise_form_error "Recipient must be an email address."
            end
            email_address
          }.compact.uniq
          @recipient_safe = recipient.collect { |r| OT::Utils.obscure_email(r) }
        end
      end
      def raise_concerns
        limit_action :create_secret
        raise_form_error "You did not provide anything to share" if kind == :share && secret_value.to_s.empty?
        raise OT::Problem, "Unknown type of secret" if kind.nil?
      end
      def process
        @metadata, @secret = Onetime::Secret.spawn_pair cust.custid, [sess.external_identifier]
        if !passphrase.empty?
          secret.update_passphrase passphrase 
          metadata.passphrase = secret.passphrase
        end
        secret.encrypt_value secret_value
        metadata.ttl, secret.ttl = ttl, ttl
        secret.maxviews = maxviews
        secret.save
        metadata.save
        if metadata.valid? && secret.valid?
          cust.add_metadata metadata unless cust.anonymous?
          cust.incr :secrets_created
          OT::Customer.global.incr :secrets_created
          unless recipient.nil? || recipient.empty?
            metadata.deliver_by_email cust, secret, recipient
          end
        else
          raise_form_error "Could not store your secret" 
        end
      end
      def redirect_uri
        ['/private/', metadata.key].join
      end
    end
    
    class ShowSecret < OT::Logic::Base
      attr_reader :key, :passphrase, :continue
      attr_reader :secret, :show_secret, :secret_value, :truncated, :original_size, :verification, :correct_passphrase
      def process_params
        @key = params[:key].to_s
        @secret = Onetime::Secret.load key
        @passphrase = params[:passphrase].to_s
        @continue = params[:continue] == 'true'
      end
      def raise_concerns
        limit_action :show_secret
        raise OT::MissingSecret if secret.nil? || !secret.viewable?
      end
      def process
        @correct_passphrase = !secret.has_passphrase? || secret.passphrase?(passphrase)
        @show_secret = secret.viewable? && correct_passphrase && continue
        @verification = secret.verification.to_s == "true"
        owner = secret.load_customer
        if show_secret
          @secret_value = secret.can_decrypt? ? secret.decrypted_value : secret.value
          @truncated = secret.truncated
          @original_size = secret.original_size
          if verification
            if cust.anonymous? || (cust.custid == owner.custid && !owner.verified?)
              owner.verified = "true"
              sess.destroy!
              secret.viewed!
            else
              raise_form_error "You can't verify an account when you're already logged in."
            end
          else
            owner.incr :secrets_shared unless owner.anonymous?
            OT::Customer.global.incr :secrets_shared
            secret.viewed!
          end
        elsif !correct_passphrase
          limit_action :failed_passphrase if secret.has_passphrase?
          # do nothing
        end
      end
    end
    
    class ShowMetadata < OT::Logic::Base
      attr_reader :key
      attr_reader :metadata, :secret, :show_secret
      def process_params
        @key = params[:key].to_s
        @metadata = Onetime::Metadata.load key
      end
      def raise_concerns
        limit_action :show_metadata
        raise OT::MissingSecret if metadata.nil?
      end
      def process
        @secret = @metadata.load_secret
        unless metadata.state?(:viewed) || metadata.state?(:shared)
          metadata.viewed!
          @show_secret = true
        end
      end
    end
  end
end
