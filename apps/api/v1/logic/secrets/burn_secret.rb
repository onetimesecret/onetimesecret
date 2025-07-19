# apps/api/v1/logic/secrets/burn_secret.rb

module V1::Logic
  module Secrets

    class BurnSecret < V1::Logic::Base
      attr_reader :key, :passphrase, :continue
      attr_reader :metadata, :secret, :correct_passphrase, :greenlighted

      def process_params
        @key = params[:key].to_s
        @metadata = V1::Metadata.load key
        @passphrase = params[:passphrase].to_s
        @continue = [true, 'true'].include?(params[:continue])
      end

      def raise_concerns
        limit_action :burn_secret
        raise OT::MissingSecret if metadata.nil?
      end

      def process
        potential_secret = @metadata.load_secret

        if potential_secret
          # Rate limit all secret access attempts
          limit_action :attempt_secret_access

          @correct_passphrase = !potential_secret.has_passphrase? || potential_secret.passphrase?(passphrase)
          viewable = potential_secret.viewable?
          continue_result = params[:continue]
          @greenlighted = viewable && correct_passphrase && continue_result
          locales = OT.conf['locales']

          if greenlighted
            @secret = potential_secret
            owner = secret.load_customer
            secret.burned!
            owner.increment_field :secrets_burned unless owner.anonymous?
            V1::Customer.global.increment_field :secrets_burned

          elsif !correct_passphrase
            limit_action :failed_passphrase if potential_secret.has_passphrase?
            message = locales.dig(locale, 'web', 'COMMON', 'error_passphrase') || 'Incorrect passphrase'
            raise_form_error message

          end
        end
      end

      def success_data
        # Get base metadata attributes
        attributes = metadata.safe_dump

        # Add required URL fields
        attributes.merge!({
          # secret_state: 'burned',
          natural_expiration: natural_duration(metadata.ttl.to_i),
          expiration: (metadata.ttl.to_i + metadata.created.to_i),
          expiration_in_seconds: (metadata.ttl.to_i),
          share_path: build_path(:secret, metadata.secret_key),
          burn_path: build_path(:private, metadata.key, 'burn'),
          metadata_path: build_path(:private, metadata.key),
          share_url: build_url(baseuri, build_path(:secret, metadata.secret_key)),
          metadata_url: build_url(baseuri, build_path(:private, metadata.key)),
          burn_url: build_url(baseuri, build_path(:private, metadata.key, 'burn')),
        })

        {
          success: greenlighted,
          record: attributes,
          details: {
            type: 'record',
            title: "Secret burned",
            display_lines: 0,
            display_feedback: false,
            no_cache: true,
            maxviews: 0,
            has_maxviews: false,
            view_count: 0,
            has_passphrase: false,
            can_decrypt: false,
            is_truncated: false,
            show_secret: false,
            show_secret_link: false,
            show_metadata_link: false,
            show_metadata: true,
            show_recipients: !metadata.recipients.to_s.empty?,
            is_orphaned: false,
          },
        }
      end

    end

  end
end
