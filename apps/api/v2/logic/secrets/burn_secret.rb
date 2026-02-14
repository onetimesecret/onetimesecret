# apps/api/v2/logic/secrets/burn_secret.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class BurnSecret < V2::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :identifier, :passphrase, :continue, :receipt, :secret, :correct_passphrase, :greenlighted

      def process_params
        @identifier = sanitize_identifier(params['identifier'])
        @receipt    = Onetime::Receipt.load identifier
        @passphrase = params['passphrase'].to_s
        @continue   = [true, 'true'].include?(params['continue'])
      end

      def raise_concerns
        require_entitlement!('api_access')
        raise OT::MissingSecret if receipt.nil?
      end

      def process
        potential_secret = @receipt.load_secret

        return unless potential_secret

        @correct_passphrase = !potential_secret.has_passphrase? || potential_secret.passphrase?(passphrase)
        viewable            = potential_secret.viewable?
        continue_result     = params['continue']
        @greenlighted       = viewable && correct_passphrase && continue_result

        secret_logger.debug 'Secret burn initiated',
          {
            receipt_identifier: receipt.identifier,
            secret_identifier: potential_secret.shortid,
            viewable: viewable,
            has_passphrase: potential_secret.has_passphrase?,
            passphrase_correct: correct_passphrase,
            continue: continue_result,
            user_id: cust&.custid,
          }

        if greenlighted
          @secret = potential_secret
          secret.burned!
          owner   = secret.load_owner
          owner&.increment_field :secrets_burned unless owner&.anonymous?
          Onetime::Customer.secrets_burned.increment

          secret_logger.info 'Secret burned successfully',
            {
              secret_identifier: secret.shortid,
              receipt_identifier: receipt.identifier,
              owner_id: owner&.custid,
              user_id: cust&.custid,
              action: 'burn',
              result: :success,
            }

        elsif !correct_passphrase
          secret_logger.warn 'Burn failed - incorrect passphrase',
            {
              receipt_identifier: receipt.identifier,
              secret_identifier: potential_secret.shortid,
              user_id: cust&.custid,
              action: 'burn',
              result: :passphrase_failed,
            }

          message = I18n.t('web.COMMON.error_passphrase', locale: locale, default: 'Incorrect passphrase')
          raise_form_error message

        end

        success_data
      end

      def success_data
        # Get base receipt attributes
        attributes = receipt.safe_dump

        # Add required URL fields
        attributes.merge!(
          {
            # secret_state: 'burned',
            natural_expiration: natural_duration(receipt.default_expiration.to_i),
            expiration: (receipt.default_expiration.to_i + receipt.created.to_i),
            expiration_in_seconds: receipt.default_expiration.to_i,
            share_path: build_path(:secret, receipt.secret_identifier),
            burn_path: build_path(:private, receipt.identifier, 'burn'),
            receipt_path: build_path(:private, receipt.identifier),
            metadata_path: build_path(:private, receipt.identifier), # maintain public API
            share_url: build_url(baseuri, build_path(:secret, receipt.secret_identifier)),
            receipt_url: build_url(baseuri, build_path(:private, receipt.identifier)),
            metadata_url: build_url(baseuri, build_path(:private, receipt.identifier)), # maintain public API
            burn_url: build_url(baseuri, build_path(:private, receipt.identifier, 'burn')),
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
            show_metadata_link: false, # maintain public API
            show_metadata: true, # maintain public API
            show_recipients: !receipt.recipients.to_s.empty?,
            is_orphaned: false,
          },
        }
      end
    end
  end
end
