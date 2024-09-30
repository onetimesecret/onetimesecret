

DEFAULT_SECRET_KIND = :share unless defined?(DEFAULT_SECRET_KIND)

module Onetime::Logic
  module Secrets

    class ConcealSecret < OT::Logic::Base
      attr_reader :passphrase, :secret_value, :kind, :ttl, :recipient, :recipient_safe, :greenlighted
      attr_reader :metadata, :secret, :share_domain, :custom_domain
      attr_accessor :token

      def process_params
        @ttl = params[:ttl].to_i
        @ttl = plan.options[:ttl] if @ttl <= 0
        @ttl = plan.options[:ttl] if @ttl >= plan.options[:ttl]
        @ttl = 5.minutes if @ttl < 1.minute

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
          # If the given domain is the same as the site's host domain, then
          # we simply skip the share domain stuff altogether.
          if OT::CustomDomain.default_domain?(potential_domain)
            OT.info "[ConcealSecret] Skipping share domain: #{potential_domain}"
          else
            @share_domain = potential_domain
          end
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
        if share_domain
          @custom_domain = OT::CustomDomain.load(@share_domain, cust.custid)

          # Is the custom domain is nil, it either doesn't exist in the system
          # or it doesn't exist in the system for this customer.
          raise_form_error "Unknown share domain (#{@share_domain})" if @custom_domain.nil?

          # We should never get here in theory since the domain won't load unless
          # the domain+custid matches. However, due to bugs and unofrseen circumstances
          # we may get here in practice.
          raise_form_error "Invalid share domain (#{@share_domain})" unless @custom_domain.owner?(@cust)
        end
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
        secret.save
        metadata.save

        @greenlighted = metadata.valid? && secret.valid?

        if greenlighted
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

      def success_data
        {
          success: greenlighted,
          record: {
            metadata: metadata.safe_dump,
            secret: secret.safe_dump,
            share_domain: share_domain
          },
          details: {
            kind: kind,
            recipient: recipient,
            recipient_safe: recipient_safe
          }
        }
      end

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
  end
end
