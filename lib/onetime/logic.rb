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

    class CreateSecret < OT::Logic::Base
      attr_reader :passphrase, :secret_value, :kind, :ttl, :recipient, :recipient_safe, :maxviews
      attr_reader :metadata, :secret, :share_domain
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

        # Capture the selected domain the link is meant for, as long as it's
        # a valid public domain (no pub intended). This is the same validation
        # that CustomDomain objects go through so if we don't get past this
        # most basic of checks, then whatever this is never had a whisker's
        # chance in a lion's den of being a custom domain anyway.
        potential_domain = params[:share_domain].to_s
        if potential_domain && OT::CustomDomain.valid?(potential_domain)
          @share_domain = potential_domain
        end
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

        # Returns the display_domain/share_domain or
        @share_domain = OT::CustomDomain.display_domain(@share_domain) if share_domain
      end

      def process
        @metadata, @secret = Onetime::Secret.spawn_pair cust.custid, token
        if !passphrase.empty?
          secret.update_passphrase passphrase
          metadata.passphrase = secret.passphrase
        end
        secret.encrypt_value secret_value, :size => plan.options[:size]
        metadata.ttl, secret.ttl = ttl*2, ttl
        metadata.secret_shortkey = secret.shortkey
        metadata.secret_ttl = secret.ttl
        metadata.share_domain = share_domain
        secret.share_domain = share_domain
        secret.maxviews = maxviews
        secret.save
        metadata.save

        if metadata.valid? && secret.valid?
          unless cust.anonymous?
            cust.add_metadata metadata
            cust.increment :secrets_created
          end

          OT::Customer.global.increment :secrets_created

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
        @metadata, @secret = Onetime::Secret.spawn_pair cust.custid, token
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
            cust.increment :secrets_created
          end
          OT::Customer.global.increment :secrets_created
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
            OT::Customer.global.increment :secrets_shared
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
            OT::Customer.global.increment :secrets_burned
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
        @metadata = cust.metadata_list
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

require_relative 'logic/account'
require_relative 'logic/welcome'
