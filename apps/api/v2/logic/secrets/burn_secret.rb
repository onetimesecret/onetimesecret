# apps/api/v2/logic/secrets/burn_secret.rb

module V2::Logic
  module Secrets

    using Familia::Refinements::TimeLiterals

    class BurnSecret < V2::Logic::Base
      attr_reader :key, :passphrase, :continue, :metadata, :secret, :correct_passphrase, :greenlighted

      def process_params
        @key        = params[:key].to_s
        @metadata   = Onetime::Metadata.load key
        @passphrase = params[:passphrase].to_s
        @continue   = [true, 'true'].include?(params[:continue])
      end

      def raise_concerns
        raise OT::MissingSecret if metadata.nil?
      end

      def process
        potential_secret = @metadata.load_secret

        return unless potential_secret

        @correct_passphrase = !potential_secret.has_passphrase? || potential_secret.passphrase?(passphrase)
        viewable            = potential_secret.viewable?
        continue_result     = params[:continue]
        @greenlighted       = viewable && correct_passphrase && continue_result

        if greenlighted
          @secret = potential_secret
          owner   = secret.load_customer
          secret.burned!
          owner.increment_field :secrets_burned unless owner.anonymous?
          Onetime::Customer.global.increment_field :secrets_burned

        elsif !correct_passphrase

          message = OT.locales.dig(locale, :web, :COMMON, :error_passphrase) || 'Incorrect passphrase'
          raise_form_error message

        end
      end

      def success_data
        # Get base metadata attributes
        attributes = metadata.safe_dump

        # Add required URL fields
        attributes.merge!({
          # secret_state: 'burned',
          natural_expiration: natural_duration(metadata.default_expiration.to_i),
          expiration: (metadata.default_expiration.to_i + metadata.created.to_i),
          expiration_in_seconds: metadata.default_expiration.to_i,
          share_path: build_path(:secret, metadata.secret_key),
          burn_path: build_path(:private, metadata.key, 'burn'),
          metadata_path: build_path(:private, metadata.key),
          share_url: build_url(baseuri, build_path(:secret, metadata.secret_key)),
          metadata_url: build_url(baseuri, build_path(:private, metadata.key)),
          burn_url: build_url(baseuri, build_path(:private, metadata.key, 'burn')),
        },
                         )

        {
          success: greenlighted,
          record: attributes,
          details: {
            type: 'record',
            title: 'Secret burned',
            display_lines: 0,
            display_feedback: false,
            no_cache: true,
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
