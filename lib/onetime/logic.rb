

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
    
    class CreateAccount < OT::Logic::Base
      attr_reader :cust
      attr_reader :planid, :custid, :password
      def process_params
        @planid = params[:planid].to_s
        @custid = params[:custid].to_s
        @password = params[:password].to_s
        @password2 = params[:password2].to_s
      end
      def raise_concerns
        raise_form_error "Username not available" if OT::Customer.exists?(@custid)
        raise_form_error "Is that a valid email address?"  unless valid_email?(custid)
        raise_form_error "Passwords do not match" unless @password == @password2
      end
      def process
        @cust = OT::Customer.create @custid
        cust.update_passphrase @password
        sess.authenticated = true
      end
      private
      def form_fields
        {:planid => planid, :custid => custid }
      end
      def valid_email?(email)
        !email.match(EMAIL_REGEX).nil?
      end
    end

    class AuthenticateSession < OT::Logic::Base
      attr_reader :custid
      def process_params
        @custid = params[:custid]
      end
      def raise_concerns
        sess.event_incr! :authenticate_session
        if @cust.nil?
          @cust ||= OT::Customer.anonymous
          u, p = params[:u], params[:p].gibbler.short
          raise_form_error "Try again"
        end
      end

      def process
        if success?
          OT.info "[login-success] #{cust.custid} #{cust.role}"
          #TODO: sess = OT::Session.new @sess.ipaddress, @sess.agent, @cust.custid
          #@sess.destroy!   # get rid of the unauthenticated session ID
          #@sess = sess
          @sess.custid = @cust.custid
          @sess.authenticated = true
          @sess.ttl = 20.days if @stay
          #OT::Customer.active.add OT.now.to_i, @cust if @cust && @sess.authenticated?
          @cust.save
        else
          raise_form_error "Try again"
        end
      end
      
      def success?
        !cust.nil? && !cust.anonymous?
      end
      
      protected 

      def process_params
        @stay = params[:stay].to_s == "true"
        if params[:u].to_s.index(':as:')
          @colonelname, @custid = *params[:u].downcase.split(':as:')
        else
          @custid = params[:u].downcase if params[:u]
        end
        if params[:p].to_s.empty?
          @cust = nil
        elsif @colonelname && OT::Customer.exists?(@colonelname) && OT::Customer.exists?(@custid)
          OT.info "[login-as-attempt] #{@colonelname} as #{@custid  } #{@sess.ipaddress}"
          @potential = OT::Customer.load @colonelname
          colonel = potential if potential.password?(params[:p])
          @cust = OT::Customer.load @custid if colonel.role?(:colonel)
          OT.info "[login-as-success] #{@colonelname} as #{@custid} #{@sess.ipaddress}"
        elsif (potential = OT::Customer.load(@custid))
          @cust = potential if potential.passphrase?(params[:p])
        #elsif OT::Customer.email_index.taken? @custid
        #  potential = OT::Customer.email_index[@custid]
        #  @cust = potential if potential.password?(params[:p])
        end
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
          @modified << :password
        end
      end
      def process
        cust.update_passphrase @newp
        cust.update_time!
        sess.set_error_message "Password changed" if modified?(:password)
        sess.set_error_message "Nothing changed" if modified.empty?
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
        @secret_value = params[:secret].to_s
        @passphrase = params[:passphrase].to_s
      end
      def raise_concerns
        sess.event_incr! :create_secret
        raise_form_error "You must provide a secret" if kind == :share && secret_value.empty?
        raise OT::Problem, "Unknown type of secret" if kind.nil?
      end
      def process
        @metadata, @secret = Onetime::Secret.generate_pair :anon, [sess.external_identifier]
        metadata.passphrase = passphrase if !passphrase.empty?
        secret.update_passphrase passphrase if !passphrase.empty?
        processed_value = case kind
        when :share
          secret_value.slice(0, 4999)
        when :generate
          @secret_value = Onetime::Utils.strand 12 # set secret_value too.
        end
        secret.original_size = secret_value.size
        secret.encrypt_value processed_value
        secret.save
        metadata.save
        raise_form_error "Could not store your secret" unless metadata.valid? && secret.valid?
      end
      def redirect_uri
        ['/private/', metadata.key].join
      end
    end
    
    class ShowSecret < OT::Logic::Base
      attr_reader :key, :passphrase, :continue
      attr_reader :secret, :show_secret, :secret_value
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
        if show_secret 
          @secret_value = secret.can_decrypt? ? secret.decrypted_value : secret.value
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