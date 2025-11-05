# apps/api/v2/logic/secrets/burn_secret.rb

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class BurnSecret < V2::Logic::Base
      include Onetime::Logging

      attr_reader :identifier, :passphrase, :continue, :metadata, :secret, :correct_passphrase, :greenlighted

      def process_params
        @identifier = params['identifier'].to_s
        @metadata   = Onetime::Metadata.load identifier
        @passphrase = params['passphrase'].to_s
        @continue   = [true, 'true'].include?(params['continue'])
      end

      def raise_concerns
        raise OT::MissingSecret if metadata.nil?
      end

      def process
        potential_secret = @metadata.load_secret

        return unless potential_secret

        @correct_passphrase = !potential_secret.has_passphrase? || potential_secret.passphrase?(passphrase)
        viewable            = potential_secret.viewable?
        continue_result     = params['continue']
        @greenlighted       = viewable && correct_passphrase && continue_result

        secret_logger.debug 'Secret burn initiated', {
          metadata_identifier: metadata.identifier,
          secret_identifier: potential_secret.shortid,
          viewable: viewable,
          has_passphrase: potential_secret.has_passphrase?,
          passphrase_correct: correct_passphrase,
          continue: continue_result,
          user_id: cust&.custid,
        }

        if greenlighted
          @secret = potential_secret
          owner   = secret.load_owner
          secret.burned!
          owner.increment_field :secrets_burned unless owner.anonymous?
          Onetime::Customer.secrets_burned.increment

          secret_logger.info 'Secret burned successfully', {
            secret_identifier: secret.shortid,
            metadata_identifier: metadata.identifier,
            owner_id: owner&.custid,
            user_id: cust&.custid,
            action: 'burn',
            result: :success,
          }

        elsif !correct_passphrase
          secret_logger.warn 'Burn failed - incorrect passphrase', {
            metadata_identifier: metadata.identifier,
            secret_identifier: potential_secret.shortid,
            user_id: cust&.custid,
            action: 'burn',
            result: :passphrase_failed,
          }

          message = OT.locales.dig(locale, :web, :COMMON, :error_passphrase) || 'Incorrect passphrase'
          raise_form_error message

        end

        success_data
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
          share_path: build_path(:secret, metadata.secret_identifier),
          burn_path: build_path(:private, metadata.identifier, 'burn'),
          metadata_path: build_path(:private, metadata.identifier),
          share_url: build_url(baseuri, build_path(:secret, metadata.secret_identifier)),
          metadata_url: build_url(baseuri, build_path(:private, metadata.identifier)),
          burn_url: build_url(baseuri, build_path(:private, metadata.identifier, 'burn')),
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
