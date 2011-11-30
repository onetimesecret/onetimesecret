

module Onetime
  module Logic
    class Base
      unless defined?(Onetime::Logic::Base::MOBILE_REGEX)
        MOBILE_REGEX = /^\+?\d{9,16}$/
        EMAIL_REGEX = %r{^(?:[_a-z0-9-]+)(\.[_a-z0-9-]+)*@([a-z0-9-]+)(\.[a-zA-Z0-9\-\.]+)*(\.[a-z]{2,4})$}i
      end
      attr_reader :sess, :cust, :params, :processed_params
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
    end
    
    class ReceiveFeedback < OT::Logic::Base
      
      def process_params
        @msg = params[:msg].to_s
      end
      
      def raise_concerns
        sess.event_incr! :send_feedback
        if @msg.empty? || @msg =~ /#{Regexp.escape(OT.conf[:site][:feedback][:text])}/
          raise_form_error "You can be more original than that!"
        end
      end
      
      def process
        OT::Feedback.add @msg
      end
    end
    
    class CreateAccount < OT::Logic::Base
      attr_reader :cust
      attr_reader :planid, :custid, :password, :password2
      def process_params
        @planid = params[:planid].to_s
        @custid = params[:custid].to_s
        @password = params[:password].to_s
        @password2 = params[:password2].to_s
      end
      def raise_concerns
        raise OT::FormError, "You're already signed up" if sess.authenticated?
        raise_form_error "Username not available" if OT::Customer.exists?(custid)
        raise_form_error "Is that a valid email address?"  unless valid_email?(custid)
        raise_form_error "Passwords do not match" unless password == password2
        raise_form_error "Password is too short" unless password.size >= 6
        raise_form_error "Unknown plan type" unless OT::Plan.plan?(planid)
      end
      def process
        @cust = OT::Customer.create custid
        cust.update_passphrase password
        sess.update_fields :custid => cust.custid, :authenticated => 'true'
        cust.update_fields :planid => planid, :verified => false
        metadata, secret = Onetime::Secret.spawn_pair cust.custid, [sess.external_identifier]
        msg = "Thanks for verifying your account.\n\n"
        # TODO: Add fortunes
        msg << "Here is your fortune cookie for today: %s" % ['A house is full of games and puzzles.']
        secret.encrypt_value msg
        secret.verification = true
        secret.custid = cust.custid
        secret.save
        view = OT::Email::Welcome.new cust, secret
        view.deliver_email
      end
      private
      def form_fields
        { :planid => planid, :custid => custid }
      end
      def valid_email?(email)
        !email.match(EMAIL_REGEX).nil?
      end
    end

    class AuthenticateSession < OT::Logic::Base
      attr_reader :custid, :stay
      
      def process_params
        @custid = params[:u]
        @passwd = params[:p]
        
        @stay = params[:stay].to_s == "true"
        if @custid.to_s.index(':as:')
          @colonelname, @custid = *@custid.downcase.split(':as:')
        else
          @custid = @custid.downcase if @custid
        end
        if @passwd.to_s.empty?
          @cust = nil
        elsif @colonelname && OT::Customer.exists?(@colonelname) && OT::Customer.exists?(@custid)
          OT.info "[login-as-attempt] #{@colonelname} as #{@custid  } #{@sess.ipaddress}"
          @potential = OT::Customer.load @colonelname
          colonel = potential if potential.password?(@passwd)
          @cust = OT::Customer.load @custid if colonel.role?(:colonel)
          OT.info "[login-as-success] #{@colonelname} as #{@custid} #{@sess.ipaddress}"
        elsif (potential = OT::Customer.load(@custid))
          @cust = potential if potential.passphrase?(@passwd)
        #elsif OT::Customer.email_index.taken? @custid
        #  potential = OT::Customer.email_index[@custid]
        #  @cust = potential if potential.password?(@passwd)
        end
      end
      
      def raise_concerns
        sess.event_incr! :authenticate_session
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
          sess.ttl = 20.days if @stay
          sess.save
          cust.save
        else
          raise_form_error "Try again"
        end
      end
      
      def success?
        !cust.nil? && !cust.anonymous?
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
        sess.event_incr! :destroy_session
      end
      def process
        sess.destroy!
      end
    end
    
    class Dashboard < OT::Logic::Base
      def process_params
      end
      def raise_concerns
        sess.event_incr! :dashboard
      end
      def process
      end
    end

    class ViewAccount < OT::Logic::Base
      def process_params
      end
      def raise_concerns
        sess.event_incr! :show_account
      end
      def process
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
        sess.event_incr! :update_account
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
          sess.set_error_message "Password changed"
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
    
    class CreateSecret < OT::Logic::Base
      attr_reader :passphrase, :secret_value, :kind
      attr_reader :metadata, :secret
      def process_params
        if ['share', 'generate'].member?(params[:kind].to_s)
          @kind = params[:kind].to_s.to_sym 
        end
        @secret_value = kind == :share ? params[:secret] : Onetime::Utils.strand(12)
        @passphrase = params[:passphrase].to_s
      end
      def raise_concerns
        sess.event_incr! :create_secret
        raise_form_error "You must provide a secret" if kind == :share && secret_value.empty?
        raise OT::Problem, "Unknown type of secret" if kind.nil?
      end
      def process
        @metadata, @secret = Onetime::Secret.spawn_pair :anon, [sess.external_identifier]
        metadata.passphrase = passphrase if !passphrase.empty?
        secret.update_passphrase passphrase if !passphrase.empty?
        secret.encrypt_value secret_value
        secret.save
        metadata.save
        if metadata.valid? && secret.valid?
          cust.add_metadata metadata unless cust.anonymous?
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
      attr_reader :secret, :show_secret, :secret_value, :truncated, :original_size, :verification
      def process_params
        @key = params[:key].to_s
        @secret = Onetime::Secret.load key
        @passphrase = params[:passphrase].to_s
        @continue = params[:continue] == 'true'
      end
      def raise_concerns
        raise OT::MissingSecret if secret.nil?
      end
      def process
        @show_secret = secret.state?(:new) && ((secret.has_passphrase? && secret.passphrase?(passphrase)) || continue)
        @verification = secret.verification.to_s == "true"
        cust.verified = true if @verification
        if show_secret 
          @secret_value = secret.can_decrypt? ? secret.decrypted_value : secret.value
          @truncated = secret.truncated
          @original_size = secret.original_size
          if secret.verification.to_s == "true" && !cust.verified?
            @verification = true
            cust.verified = "true"
          end
          secret.viewed!
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
        raise OT::MissingSecret if metadata.nil?
      end
      def process
        @secret = @metadata.load_secret
        # We temporarily store the raw passphrase when the private
        # secret is created so we can display it once. Here we 
        # update it with the encrypted one.
        unless metadata.state?(:viewed) || metadata.state?(:shared)
          secret.passphrase_temp = metadata.passphrase
          metadata.passphrase = secret.passphrase
          metadata.viewed!
          @show_secret = true
        end
      end
    end
  end
end