
require_relative 'base'

DEFAULT_SECRET_KIND = :share unless defined?(DEFAULT_SECRET_KIND)

module Onetime::Logic
  module Secrets

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
        @kind = DEFAULT_SECRET_KIND if kind.nil? # assume share, not sonny

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
        if !@recipient.empty?
          raise_form_error "An account is required to send emails." if cust.anonymous?
          @recipient.each do |recip|
            raise_form_error "Undeliverable email address: #{recip}" unless valid_email?(recip)
          end
        end

        raise_form_error "Unknown type of secret" if kind.nil?

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
            cust.increment_field :secrets_created
          end

          OT::Customer.global.increment_field :secrets_created

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

      #private

      def form_fields
        {
          share_domain: share_domain,
          secret: secret_value,
          recipient: recipient,
          ttl: ttl,
          kind: kind
        }
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
          @truncated = secret.truncated?
          @original_size = secret.original_size

          if verification
            if cust.anonymous? || (cust.custid == owner.custid && !owner.verified?)
              owner.verified! "true"
              sess.destroy!
              secret.received!
            else
              raise_form_error "You can't verify an account when you're already logged in."
            end
          else

            owner.increment_field :secrets_shared unless cust.anonymous?
            OT::Customer.global.increment_field :secrets_shared

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

            owner.increment_field :secrets_burned unless owner.anonymous?
            OT::Customer.global.increment_field :secrets_burned

            secret.burned!

            OT::Logic.stathat_count('Burned Secrets', 1)
          elsif !correct_passphrase
            limit_action :failed_passphrase if secret.has_passphrase?
            # do nothing
          end
        end
      end

    end
  end
end
