# apps/api/v1/logic/secrets/burn_secret.rb
#
# frozen_string_literal: true

module V1::Logic
  module Secrets

    using Familia::Refinements::TimeLiterals

    class BurnSecret < V1::Logic::Base
      attr_reader :key, :passphrase, :continue
      attr_reader :receipt, :secret, :correct_passphrase, :greenlighted

      def process_params
        @key = sanitize_identifier(params['key'])
        @receipt = Onetime::Receipt.load key
        @passphrase = params['passphrase'].to_s
        @continue = [true, 'true'].include?(params['continue'])
      end

      def raise_concerns

        raise OT::MissingSecret if receipt.nil?
      end

      def process
        potential_secret = @receipt.load_secret

        if potential_secret


          @correct_passphrase = !potential_secret.has_passphrase? || potential_secret.passphrase?(passphrase)
          viewable = potential_secret.viewable?
          continue_result = params['continue']
          @greenlighted = viewable && correct_passphrase && continue_result

          if greenlighted
            @secret = potential_secret
            owner = secret.load_customer
            secret.burned!
            owner.increment_field :secrets_burned unless owner.anonymous?
            # TODO:
            # Onetime::Customer.global.increment_field :secrets_burned

          elsif !correct_passphrase

            message = I18n.t('web.COMMON.error_passphrase', locale: locale, default: 'Incorrect passphrase')
            raise_form_error message

          end
        end
      end

      def success_data
        # Get base receipt attributes
        attributes = receipt.safe_dump

        # Add required URL fields
        attributes.merge!({
          # secret_state: 'burned',
          natural_expiration: natural_duration(receipt.default_expiration.to_i),
          expiration: (receipt.default_expiration.to_i + receipt.created.to_i),
          expiration_in_seconds: (receipt.default_expiration.to_i),
          share_path: build_path(:secret, receipt.secret_key),
          burn_path: build_path(:private, receipt.key, 'burn'),
          metadata_path: build_path(:private, receipt.key), # maintain public API
          share_url: build_url(baseuri, build_path(:secret, receipt.secret_key)),
          metadata_url: build_url(baseuri, build_path(:private, receipt.key)), # maintain public API
          burn_url: build_url(baseuri, build_path(:private, receipt.key, 'burn')),
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
            view_count: 0,
            has_passphrase: false,
            can_decrypt: false,
            is_truncated: false,
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
