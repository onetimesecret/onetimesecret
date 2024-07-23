require 'stathat'
require 'timeout'

require_relative 'logic/base'

module Onetime
  module Logic

    class ReceiveFeedback < OT::Logic::Base
      attr_reader :msg
      def process_params
        @msg = params[:msg].to_s.slice(0, 999)
      end

      def raise_concerns
        limit_action :send_feedback
        raise_form_error "You need an account to do that" if cust.anonymous?
        if @msg.empty? || @msg =~ /#{Regexp.escape("question or comment")}/
          raise_form_error "You can be more original than that!"
        end
      end

      def process
        @msg = "#{msg} [%s]" % [cust.anonymous? ? sess.ipaddress : cust.custid]
        OT.ld [:receive_feedback, msg].inspect
        OT::Feedback.add @msg
        sess.set_info_message "Message received. Send as much as you like!"
      end
    end

    class CreateAccount < OT::Logic::Base
      attr_reader :cust, :plan, :autoverify, :customer_role
      attr_reader :planid, :custid, :password, :password2, :skill
      attr_accessor :token
      def process_params
        @planid = params[:planid].to_s
        @custid = params[:u].to_s.downcase.strip
        @password = params[:p].to_s
        @password2 = params[:p2].to_s

        @autoverify = OT.conf&.dig(:site, :authentication, :autoverify) || false

        # This is a hidden field, so it should be empty. If it has a value, it's
        # a simple bot trying to submit the form or similar chicanery. We just
        # quietly redirect to the home page to mimic a successful response.
        @skill = params[:skill].to_s
      end
      def raise_concerns
        limit_action :create_account
        raise OT::FormError, "You're already signed up" if sess.authenticated?
        raise_form_error "Username not available" if OT::Customer.exists?(custid)
        raise_form_error "Is that a valid email address?" unless valid_email?(custid)
        raise_form_error "Passwords do not match" unless password == password2
        raise_form_error "Password is too short" unless password.size >= 6
        raise_form_error "Unknown plan type" unless OT::Plan.plan?(planid)

        # This is a hidden field, so it should be empty. If it has a value, it's
        # a simple bot trying to submit the form or similar chicanery. We just
        # quietly redirect to the home page to mimic a successful response.
        unless skill.empty?
          raise OT::Redirect.new('/?s=1') # the query string is just an arbitrary value for the logs
        end
      end
      def process


        @plan = OT::Plan.plan(planid)
        @cust = OT::Customer.create custid

        cust.update_passphrase password
        sess.update_fields(custid: cust.custid)

        @customer_role = if OT.conf[:colonels].member?(cust.custid)
                           'colonel'
                         else
                           'customer'
                         end

        cust.update_fields(planid: @plan.planid, verified: @autoverify.to_s, role: @customer_role)

        OT.info "[new-customer] #{cust.custid} #{cust.role} #{sess.ipaddress} #{plan.planid} #{sess.short_identifier}"
        OT::Logic.stathat_count("New Customers (OTS)", 1)

        if autoverify
          sess.set_info_message "Account created"
        else
          self.send_verification_email
        end

      end

      private

      def send_verification_email
        _, secret = Onetime::Secret.spawn_pair cust.custid, [sess.external_identifier], token

        msg = "Thanks for verifying your account. We got you a secret fortune cookie!\n\n\"%s\"" % OT::Utils.random_fortune

        secret.encrypt_value msg
        secret.verification = true
        secret.custid = cust.custid
        secret.save

        view = OT::App::Mail::Welcome.new cust, locale, secret

        begin
          view.deliver_email self.token

        rescue StandardError => ex
          errmsg = "Couldn't send the verification email. Let us know below."
          OT.le "Error sending verification email: #{ex.message}"
          sess.set_info_message errmsg
        end
      end

      def form_fields
        { :planid => planid, :custid => custid }
      end
    end

    class AuthenticateSession < OT::Logic::Base
      attr_reader :custid, :stay
      attr_reader :session_ttl

      def process_params
        @potential_custid = params[:u].to_s.downcase.strip
        @passwd = params[:p]
        #@stay = params[:stay].to_s == "true"
        @stay = true # Keep sessions alive by default
        @session_ttl = (stay ? 30.days : 20.minutes).to_i
        if @potential_custid.to_s.index(':as:')
          @colonelname, @potential_custid = *@potential_custid.downcase.split(':as:')
        else
          @potential_custid = @potential_custid.downcase if @potential_custid
        end
        if @passwd.to_s.empty?
          @cust = nil
        elsif @colonelname && OT::Customer.exists?(@colonelname) && OT::Customer.exists?(@potential_custid)
          OT.info "[login-as-attempt] #{@colonelname} as #{@potential_custid} #{@sess.ipaddress}"
          potential = OT::Customer.load @colonelname
          @colonel = potential if potential.passphrase?(@passwd)
          @cust = OT::Customer.load @potential_custid if @colonel.role?(:colonel)
          sess['authenticated_by'] = @colonel.custid
          OT.info "[login-as-success] #{@colonelname} as #{@potential_custid} #{@sess.ipaddress}"
        elsif (potential = OT::Customer.load(@potential_custid))
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
        !cust&.anonymous? && (cust.passphrase?(@passwd) || @colonel&.passphrase?(@passwd))
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
        OT.info "[destroy-session] #{@custid} #{@sess.ipaddress}"
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
      attr_accessor :token
      def process_params
        @custid = params[:u].to_s.downcase
      end

      def raise_concerns
        limit_action :forgot_password_request
        raise_form_error "Not a valid email address" unless valid_email?(@custid)
        raise_form_error "No account found" unless OT::Customer.exists?(@custid)
      end

      def process
        cust = OT::Customer.load @custid
        secret = OT::Secret.create @custid, [@custid]
        secret.ttl = 24.hours
        secret.verification = true

        view = OT::App::Mail::PasswordRequest.new cust, locale, secret
        view.emailer.from = OT.conf[:emailer][:from]
        view.emailer.fromname = OT.conf[:emailer][:fromname]

        OT.ld "Calling deliver_email with token=(#{self.token})"

        begin
          view.deliver_email self.token

        rescue StandardError => ex
          errmsg = "Couldn't send the notification email. Let know below."
          OT.le "Error sending password reset email: #{ex.message}"
          sess.set_info_message errmsg
        else
          sess.set_info_message "We sent instructions to #{cust.custid}"
        end

      end

      def form_fields
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
        limit_action :forgot_password_reset
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
        if cname.empty?
          sess.set_error_message "Nothing changed"
        else
          OT::Subdomain.rem cust['cname']
          subdomain.update_cname cname
          subdomain.update_fields properties
          cust.update_fields :cname => subdomain.cname
          OT::Subdomain.add cname, cust.custid
          sess.set_info_message "Branding updated"
        end
        sess.set_form_fields form_fields # for tabindex
      end

      private

      def form_fields
        properties.merge :tabindex => params[:tabindex], :cname => cname
      end
    end

    class UpdateAccount < OT::Logic::Base
      attr_reader :modified, :greenlighted

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
          raise_form_error "Current password is incorrect" unless cust.passphrase?(@currentp)
          raise_form_error "New password cannot be the same as current password" if @newp == @currentp
          raise_form_error "New password is too short" unless @newp.size >= 6
          raise_form_error "New passwords do not match" unless @newp == @newp2
        end
        if ! @passgen_token.empty?
          raise_form_error "Token is too short" if @passgen_token.size < 6
        end
      end

      def process
        if cust.passphrase?(@currentp) && @newp == @newp2
          @greenlighted = true
          OT.info "[update-account] Password updated cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress}"

          cust.update_passphrase @newp
          @modified << :password
        end
      end

      def modified? field_name
        modified.member? field_name
      end

      private

      def form_fields
        { :tabindex => params[:tabindex] }
      end
    end

    class DestroyAccount < OT::Logic::Base
      attr_reader :raised_concerns_was_called, :greenlighted

      def process_params
        unless params.nil?
          @confirmation = params[:confirmation].to_s.strip.slice(0,60)
        end
      end

      def raise_concerns
        @raised_concerns_was_called = true

        # It's vitally important for the limiter to run prior to any
        # other concerns. This prevents a malicious user from
        # attempting to brute force the password.
        #
        limit_action :destroy_account

        if @confirmation&.empty?
          raise_form_error "Password confirmation is required."
        else
          OT.info "[destroy-account] Passphrase check attempt cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress}"

          unless cust.passphrase?(@confirmation)
            raise_form_error "Please check the password."
          end
        end
      end

      def process
        # This is very defensive programming. When it comes to
        # destroying things though, let's pull out all the stops.
        unless raised_concerns_was_called
          raise_form_error "We have concerns about that request."
        end

        if cust.passphrase?(@confirmation)
          # All criteria to destroy the account have been met.
          @greenlighted = true

          # Process the customer's request to destroy their account.
          if Onetime.debug
            OT.ld "[destroy-account] Simulated account destruction #{cust.custid} #{cust.role} #{sess.ipaddress}"

            # We add a message to the session to let the debug user know
            # that we made it to this point in the logic. Otherwise, they
            # might not know if the action was successful or not since we
            # don't actually destroy the account in debug mode.
            sess.set_info_message 'Account deleted'

          else
            cust.destroy_requested!

            # Log the event immediately after saving the change to
            # to minimize the chance of the event not being logged.
            OT.info "[destroy-account] Account destroyed. #{cust.custid} #{cust.role} #{sess.ipaddress}"
          end

          # We replace the session and session ID and then add a message
          # for the user so that when the page they're directed to loads
          # (i.e. the homepage), they'll see it and remember what they did.
          sess.replace!
          sess.set_info_message 'Account deleted'
        end

        sess.set_form_fields form_fields  # for tabindex
      end

      def modified? guess
        modified.member? guess
      end

      private
      def form_fields
        { :tabindex => params[:tabindex] } unless params.nil?
      end
    end

    class GenerateAPIkey < OT::Logic::Base
      attr_reader :apikey, :greenlighted

      def process_params
      end

      def raise_concerns
        limit_action :generate_apikey

        if (!sess.authenticated?) || (cust.anonymous?)
          raise_form_error "Sorry, we don't support that"
        end
      end

      def process
        @apikey = cust.regenerate_apitoken

        @greenlighted = true
      end

      private
      def form_fields
        { :tabindex => params[:tabindex] }
      end
    end

    class CreateSecret < OT::Logic::Base
      attr_reader :passphrase, :secret_value, :kind, :ttl, :recipient, :recipient_safe, :maxviews
      attr_reader :metadata, :secret
      attr_accessor :token
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
          email_address.scan(r).uniq.first
        }.compact.uniq
        @recipient_safe = recipient.collect { |r| OT::Utils.obscure_email(r) }
      end
      def raise_concerns
        limit_action :create_secret
        limit_action :email_recipient unless recipient.empty?
        if kind == :share && secret_value.to_s.empty?
          raise_form_error "You did not provide anything to share" #
        end
        if cust.anonymous? && !@recipient.empty?
          raise_form_error "An account is required to send emails. Signup here: https://#{OT.conf[:site][:host]}"
        end
        raise OT::Problem, "Unknown type of secret" if kind.nil?
      end
      def process
        @metadata, @secret = Onetime::Secret.spawn_pair cust.custid, [sess.external_identifier], token
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
            klass = OT::App::Mail::SecretLink
            metadata.deliver_by_email cust, locale, secret, recipient.first, klass
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
      attr_accessor :token
      def process_params
        @ttl = 7.days
        @secret_value = params[:secret]
        @ticketno = params[:ticketno].strip
        @passphrase = OT.conf[:incoming][:passphrase].strip
        params[:recipient] = [OT.conf[:incoming][:email]]
        r = Regexp.new(/\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}\b/)
        @recipient = params[:recipient].collect { |email_address|
          next if email_address.to_s.empty?

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
        @metadata, @secret = Onetime::Secret.spawn_pair cust.custid, [sess.external_identifier], token
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
            metadata.deliver_by_email cust, locale, secret, recipient.first, OT::App::Mail::IncomingSupport, ticketno
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
      attr_reader :metadata, :secret, :correct_passphrase, :greenlighted

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
          @greenlighted = secret.viewable? && correct_passphrase && continue
          owner = secret.load_customer
          if greenlighted
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
