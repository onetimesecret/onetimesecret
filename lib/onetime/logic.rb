require 'stathat'
require 'timeout'

module Onetime
  module Logic
    class << self
      attr_writer :stathat_apikey, :stathat_enabled
      def stathat_apikey
        @stathat_apikey ||= Onetime.conf[:stathat][:apikey]
      end
      def stathat_enabled
        @stathat_enabled = Onetime.conf[:stathat][:enabled] if @stathat_enabled.nil?
        @stathat_enabled
      end
      def stathat_count name, count, wait=0.500
        return false if ! stathat_enabled
        begin
          timeout(wait) do
            StatHat::API.ez_post_count(name, stathat_apikey, count)
          end
        rescue SocketError => ex
          OT.info "Cannot connect to StatHat: #{ex.message}"
        rescue Timeout::Error
          OT.info "timeout calling stathat"
        end
      end
      def stathat_value name, value, wait=0.500
        return false if ! stathat_enabled
        begin
          Timeout.timeout(wait) do
            StatHat::API.ez_post_value(name, stathat_apikey, value)
          end
        rescue SocketError => ex
          OT.info "Cannot connect to StatHat: #{ex.message}"
        rescue Timeout::Error
          OT.info "timeout calling stathat"
        end
      end
    end
    class Base
      unless defined?(Onetime::Logic::Base::MOBILE_REGEX)
        MOBILE_REGEX = /^\+?\d{9,16}$/
        EMAIL_REGEX = %r{^(?:[_a-z0-9-]+)(\.[_a-z0-9-]+)*@([a-z0-9-]+)(\.[a-zA-Z0-9\-\.]+)*(\.[a-z]{2,12})$}i
      end
      attr_reader :sess, :cust, :params, :locale, :processed_params, :plan
      def initialize(sess, cust, params=nil, locale=nil)
        @sess, @cust, @params, @locale = sess, cust, params, locale
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
        @custid = params[:u].to_s.downcase.strip
        @password = params[:p].to_s
        @password2 = params[:p2].to_s
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
        view = OT::Email::Welcome.new cust, locale, secret
        view.deliver_email
        if OT.conf[:colonels].member?(cust.custid)
          cust.role = :colonel
        else
          cust.role = :customer unless cust.role?(:customer)
        end
        OT::Logic.stathat_count("New Customers (OTS)", 1)
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
        @custid = params[:u].to_s.downcase.strip
        @passwd = params[:p]
        #@stay = params[:stay].to_s == "true"
        @stay = true # Keep sessions alive by default
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
          sess['authenticated_by'] = @colonel.custid
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
          #TODO: get rid of the unauthenticated session ID
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
        view = OT::Email::PasswordRequest.new cust, locale, secret
        ret = view.deliver_email
        # sess.set_info_message "We sent instructions to #{cust.custid}"
        if ret.code == 200
          sess.set_info_message "We sent instructions to #{cust.custid}"
        else
          errmsg = "Couldn't send the notification email. Let know below."
          sess.set_info_message errmsg
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

    class UpdateSubdomain < OT::Logic::Base
      attr_reader :subdomain, :cname, :properties
      def process_params
        @cname = params[:cname].to_s.downcase.strip.slice(0,30)
        @properties = {
          :company => params[:company].to_s.strip.slice(0,120),
          :homepage => params[:homepage].to_s.strip.slice(0,120),
          :contact => params[:contact].to_s.strip.slice(0,60),
          :email => params[:email].to_s.strip.slice(0,120),
          :logo_uri => params[:logo_uri].to_s.strip.slice(0,120),
          :primary_color => params[:cp].to_s.strip.slice(0,30),
          :secondary_color => params[:cs].to_s.strip.slice(0,30),
          :border_color => params[:cb].to_s.strip.slice(0,30)
        }
      end
      def raise_concerns
        limit_action :update_branding
        if %w{www yourcompany mycompany admin ots secure secrets}.member?(@cname)
          raise_form_error "That CNAME is not available"
        elsif ! @cname.empty?
          @subdomain = OT::Subdomain.load_by_cname(@cname)
          raise_form_error "That CNAME is not available" if subdomain && !subdomain.owner?(cust.custid)
        end
        if ! properties[:logo_uri].empty?
          begin
            URI.parse properties[:logo_uri]
          rescue => ex
            raise_form_error "Check the logo URI"
          end
        end
      end
      def process
        @subdomain ||= OT::Subdomain.create cust.custid, @cname
        if ! cname.empty?
          OT::Subdomain.rem cust['cname']
          subdomain.update_cname cname
          subdomain.update_fields properties
          cust.update_fields :cname => subdomain.cname
          OT::Subdomain.add cname, cust.custid
          sess.set_info_message "Branding updated"
        else
          sess.set_error_message "Nothing changed"
        end
        sess.set_form_fields form_fields # for tabindex
      end
      private
      def form_fields
        properties.merge :tabindex => params[:tabindex], :cname => cname
      end
    end

    class UpdateAccount < OT::Logic::Base
      attr_reader :modified, :subdomain
      def process_params
        @currentp = params[:currentp].to_s.strip.slice(0,60)
        @newp = params[:newp].to_s.strip.slice(0,60)
        @newp2 = params[:newp2].to_s.strip.slice(0,60)
        @passgen_token = params[:passgen_token].to_s.strip.slice(0,60)
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
        if ! @passgen_token.empty?
          raise_form_error "Token is too short" if @passgen_token.size < 6
        end
      end
      def process
        if cust.passphrase?(@currentp) && @newp == @newp2
          cust.update_passphrase @newp
          @modified << :password
          sess.set_info_message "Password changed"
        end
        if ! @passgen_token.empty?
          cust.update_passgen_token @passgen_token
          @modified << :token
          sess.set_info_message "Token changed"
        end
        sess.set_error_message "Nothing changed" if modified.empty?
        sess.set_form_fields form_fields # for tabindex
      end
      def modified? guess
        modified.member? guess
      end
      private
      def form_fields
        { :tabindex => params[:tabindex] }
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
        sess.set_form_fields form_fields
        sess.set_info_message "Key changed"
      end
      private
      def form_fields
        { :tabindex => params[:tabindex] }
      end
    end

    class CreateSecret < OT::Logic::Base
      attr_reader :passphrase, :secret_value, :kind, :ttl, :recipient, :recipient_safe, :maxviews
      attr_reader :metadata, :secret
      def process_params
        @ttl = params[:ttl].to_i
        @ttl = plan.options[:ttl] if @ttl <= 0
        @ttl = plan.options[:ttl] if @ttl >= plan.options[:ttl]
        @ttl = 5.minutes if @ttl < 1.minute
        @maxviews = params[:maxviews].to_i
        @maxviews = 1 if @maxviews < 1
        @maxviews = (plan.options[:maxviews] || 100) if @maxviews > (plan.options[:maxviews] || 100)  # TODO
         if ['share', 'generate'].member?(params[:kind].to_s)
          @kind = params[:kind].to_s.to_sym
        end
        @secret_value = kind == :share ? params[:secret] : Onetime::Utils.strand(12)
        @passphrase = params[:passphrase].to_s
        params[:recipient] = [params[:recipient]].flatten.compact.uniq
        r = Regexp.new(/\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b/)
        @recipient = params[:recipient].collect { |email_address|
          next if email_address.to_s.empty?
          next if email_address =~ /#{Regexp.escape(OT.conf[:text][:paid_recipient_text])}/
          #unless valid_email?(email_address) #|| valid_mobile?(email_address)
          #  raise_form_error "Recipient must be an email address."
          #end
          email_address.scan(r).uniq.first
        }.compact.uniq
        @recipient_safe = recipient.collect { |r| OT::Utils.obscure_email(r) }
      end
      def raise_concerns
        limit_action :create_secret
        limit_action :email_recipient unless recipient.empty?
        if kind == :share && secret_value.to_s.empty?
          raise_form_error "You did not provide anything to share"
        end
        if cust.anonymous? && !@recipient.empty?
          raise_form_error "An account is required to send emails. Signup here: http://#{OT.conf[:site][:host]}"
        end
        raise OT::Problem, "Unknown type of secret" if kind.nil?
      end
      def process
        @metadata, @secret = Onetime::Secret.spawn_pair cust.custid, [sess.external_identifier]
        if !passphrase.empty?
          secret.update_passphrase passphrase
          metadata.passphrase = secret.passphrase
        end
        secret.encrypt_value secret_value, :size => plan.options[:size]
        metadata.ttl, secret.ttl = ttl*2, ttl
        metadata.secret_shortkey = secret.shortkey
        metadata.secret_ttl = secret.ttl
        secret.maxviews = maxviews
        secret.save
        metadata.save
        if metadata.valid? && secret.valid?
          unless cust.anonymous?
            cust.add_metadata metadata
            cust.incr :secrets_created
          end
          OT::Customer.global.incr :secrets_created
          unless recipient.nil? || recipient.empty?
            metadata.deliver_by_email cust, locale, secret, recipient.first
          end
          OT::Logic.stathat_count("Secrets", 1)
        else
          raise_form_error "Could not store your secret"
        end
      end
      def redirect_uri
        ['/private/', metadata.key].join
      end
      private
      def form_fields
      end
    end

    class CreateIncoming < OT::Logic::Base
      attr_reader :passphrase, :secret_value, :ticketno
      attr_reader :metadata, :secret, :recipient, :ttl
      def process_params
        @ttl = 7.days
        @secret_value = params[:secret]
        @ticketno = params[:ticketno].strip
        @passphrase = OT.conf[:incoming][:passphrase].strip
        params[:recipient] = [OT.conf[:incoming][:email]]
        r = Regexp.new(/\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b/)
        @recipient = params[:recipient].collect { |email_address|
          next if email_address.to_s.empty?
          next if email_address =~ /#{Regexp.escape(OT.conf[:text][:paid_recipient_text])}/
          #unless valid_email?(email_address) #|| valid_mobile?(email_address)
          #  raise_form_error "Recipient must be an email address."
          #end
          email_address.scan(r).uniq.first
        }.compact.uniq
      end
      def raise_concerns
        limit_action :create_secret
        limit_action :email_recipient unless recipient.empty?
        regex = Regexp.new(OT.conf[:incoming][:regex] || '\A[a-zA-Z0-9]{1,32}\z')
        if secret_value.to_s.empty?
          raise_form_error "You did not provide any information to share"
        end
        if ticketno.to_s.empty? || !ticketno.match(regex)
          raise_form_error "You must provide a valid ticket number"
        end
      end
      def process
        @metadata, @secret = Onetime::Secret.spawn_pair cust.custid, [sess.external_identifier]
        if !passphrase.empty?
          secret.update_passphrase passphrase
          metadata.passphrase = secret.passphrase
        end
        secret.encrypt_value secret_value, :size => plan.options[:size]
        metadata.ttl, secret.ttl = ttl, ttl
        metadata.secret_shortkey = secret.shortkey
        secret.save
        metadata.save
        if metadata.valid? && secret.valid?
          unless cust.anonymous?
            cust.add_metadata metadata
            cust.incr :secrets_created
          end
          OT::Customer.global.incr :secrets_created
          unless recipient.nil? || recipient.empty?
            metadata.deliver_by_email cust, locale, secret, recipient.first, OT::Email::IncomingSupport, ticketno
          end
          OT::Logic.stathat_count("Secrets", 1)
        else
          raise_form_error "Could not store your secret"
        end
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
              secret.received!
            else
              raise_form_error "You can't verify an account when you're already logged in."
            end
          else
            owner.incr :secrets_shared unless owner.anonymous?
            OT::Customer.global.incr :secrets_shared
            secret.received!
            OT::Logic.stathat_count("Viewed Secrets", 1)
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
      end
    end

    class BurnSecret < OT::Logic::Base
      attr_reader :key, :passphrase, :continue
      attr_reader :metadata, :secret, :correct_passphrase, :burn_secret
      def process_params
        @key = params[:key].to_s
        @metadata = Onetime::Metadata.load key
        @passphrase = params[:passphrase].to_s
        @continue = params[:continue] == 'true'
      end
      def raise_concerns
        limit_action :burn_secret
        raise OT::MissingSecret if metadata.nil?
      end
      def process
        @secret = @metadata.load_secret
        if secret
          @correct_passphrase = !secret.has_passphrase? || secret.passphrase?(passphrase)
          @burn_secret = secret.viewable? && correct_passphrase && continue
          owner = secret.load_customer
          if burn_secret
            owner.incr :secrets_burned unless owner.anonymous?
            OT::Customer.global.incr :secrets_burned
            secret.burned!
            OT::Logic.stathat_count('Burned Secrets', 1)
          elsif !correct_passphrase
            limit_action :failed_passphrase if secret.has_passphrase?
            # do nothing
          end
        end
      end
    end

    class ShowRecentMetadata < OT::Logic::Base
      attr_reader :metadata
      def process_params
        @metadata = cust.metadata
      end
      def raise_concerns
        limit_action :show_metadata
        raise OT::MissingSecret if metadata.nil?
      end
      def process
      end
    end

  end
end
