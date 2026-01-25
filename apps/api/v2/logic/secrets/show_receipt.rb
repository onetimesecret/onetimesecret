# apps/api/v2/logic/secrets/show_receipt.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    class ShowReceipt < V2::Logic::Base
      # Working variables
      attr_reader :identifier, :receipt, :secret
      # Template variables
      attr_reader :receipt_identifier,
        :metadata_shortid,
        :secret_identifier,
        :secret_state,
        :secret_shortid,
        :recipients,
        :no_cache,
        :expiration_in_seconds,
        :natural_expiration,
        :is_received,
        :is_burned,
        :secret_realttl,
        :is_destroyed,
        :expiration,
        :view_count,
        :has_passphrase,
        :can_decrypt,
        :secret_value,
        :show_secret,
        :show_secret_link,
        :show_metadata_link,
        :metadata_attributes,
        :show_metadata,
        :show_recipients,
        :share_domain,
        :is_orphaned,
        :share_path,
        :burn_path,
        :receipt_path,
        :metadata_path,
        :share_url,
        :is_expired,
        :receipt_url,
        :metadata_url,
        :burn_url,
        :display_lines

      def process_params
        @identifier = sanitize_identifier(params['identifier'])
        @receipt    = Onetime::Receipt.load identifier
      end

      def raise_concerns
        require_entitlement!('api_access')
        raise OT::MissingSecret, "identifier: #{identifier}" if receipt.nil?
      end

      def process # rubocop:disable Metrics/MethodLength,Metrics/PerceivedComplexity
        @secret = @receipt.load_secret

        @receipt_identifier        = receipt.identifier
        @metadata_short_identifier = receipt.shortid
        @secret_identifier         = receipt.secret_identifier
        @secret_shortid            = receipt.secret_shortid

        # Default the recipients to an empty string. When a Familia::Horreum
        # object is loaded, the fields that have no values (or that don't
        # exist in the db hash yet) will have a value of "" (empty string).
        # But for a newly instantiated object, the fields will have a value
        # of nil. Later on, we rely on being able to check for emptiness
        # like: `@recipients.empty?`.
        @recipients = receipt.recipients.to_s

        @no_cache = true

        @natural_expiration    = receipt.secret_natural_duration
        @expiration            = receipt.secret_expiration
        @expiration_in_seconds = receipt.secret_ttl

        secret = receipt.load_secret

        if secret.nil?

          burned_or_revealed = receipt.state?(:burned) || receipt.state?(:revealed) || receipt.state?(:received)

          if !burned_or_revealed && receipt.secret_expired?
            OT.le("[show_receipt] Receipt has expired secret. #{receipt.shortid}")
            receipt.secret_identifier = nil
            receipt.expired!
          elsif !burned_or_revealed
            OT.le("[show_receipt] Receipt is an orphan. #{receipt.shortid}")
            receipt.secret_identifier = nil
            receipt.orphaned!
          end

          # Check for both new 'revealed' state and legacy 'received' state
          @is_received  = receipt.state?(:revealed) || receipt.state?(:received)
          @is_burned    = receipt.state?(:burned)
          @is_expired   = receipt.state?(:expired)
          @is_orphaned  = receipt.state?(:orphaned)
          @is_destroyed = @is_burned || @is_received || @is_expired || @is_orphaned

          receipt.secret_identifier! nil if is_destroyed && receipt.secret_identifier
        else
          @secret_state   = secret.state
          @secret_realttl = secret.current_expiration
          @view_count     = nil

          if secret.viewable?
            @has_passphrase = !secret.passphrase.to_s.empty?
            @can_decrypt    = secret.can_decrypt?
            # If we can't decrypt the secret (i.e. if we can't access it) then
            # then we leave secret_value nil. We do this so that after creating
            # a secret we can show the received contents on the "/receipt/receipt_identifier"
            # page one time. Particularly for generated passwords which are not
            # shown any other time.
            #
            # TODO: There's a bug here. If the UI that created this secret+receipt
            # records doesn't immediately load the receipt page the receipt
            # record stays in state=new allowing the next request through.
            if secret && receipt.state?(:new)
              OT.ld "[show_receipt] m:#{receipt_identifier} s:#{secret_identifier} Decrypting for first and only creator viewing"
              @secret_value = secret.ciphertext.reveal { it }
            end
          end
        end

        # Show the secret if it exists and hasn't been seen yet.
        #
        # It will be true if:
        #   1. The secret is not nil (i.e., a secret exists), AND
        #   2. The receipt state is NOT in any of these states: previewed/viewed,
        #      revealed/received, or burned
        #
        # Note: Check both new states (previewed, revealed) and legacy states (viewed, received)
        secret_consumed = receipt.state?(:previewed) || receipt.state?(:viewed) ||
                          receipt.state?(:revealed) || receipt.state?(:received) ||
                          receipt.state?(:burned) || receipt.state?(:orphaned)
        @show_secret    = !secret.nil? && !has_passphrase && !secret_consumed

        # The secret link is shown only when appropriate, considering the
        # state, ownership, and recipient information.
        #
        # It will be true if ALL of these conditions are met:
        #   1. The receipt state is NOT revealed/received or burned, AND
        #   2. The secret is showable (@show_secret is true), AND
        #   3. There are no recipients specified (@recipients is nil)
        #
        @show_secret_link = !(receipt.state?(:revealed) || receipt.state?(:received) || receipt.state?(:burned) || receipt.state?(:orphaned)) &&
                            @show_secret &&
                            @recipients.empty?

        # A simple check to show the receipt link only for newly
        # created secrets.
        #
        @show_metadata_link = receipt.state?(:new)

        # Allow the receipt to be shown if it hasn't been previewed/viewed yet OR
        # if the current user owns it (regardless of its previewed/viewed state).
        #
        # It will be true if EITHER of these conditions are met:
        #   1. The receipt state is NOT 'previewed' or 'viewed', OR
        #   2. The current customer is the owner of the receipt
        #
        @show_metadata = !(receipt.state?(:previewed) || receipt.state?(:viewed)) || receipt.owner?(cust)

        # Recipient information is only displayed when the receipt is
        # visible and there are actually recipients to show.
        #
        # It will be true if BOTH of these conditions are met:
        #   1. The receipt should be shown (@show_metadata is true), AND
        #   2. There are recipients specified (@recipients is not empty)
        #
        @show_recipients = @show_metadata && !@recipients.empty?

        domain = if domains_enabled
                   if receipt.share_domain.to_s.empty?
                     site_host
                   else
                     receipt.share_domain
                   end
                 else
                   site_host
                 end

        @share_domain = [base_scheme, domain].join
        OT.ld "[process] Set @share_domain: #{@share_domain}"
        process_uris

        # Dump the receipt attributes before marking as previewed
        @metadata_attributes = _metadata_attributes

        # We mark the receipt record previewed so that we can support showing the
        # secret link on the receipt page, just the one time.
        receipt.previewed! if receipt.state?(:new)

        success_data
      end

      def one_liner
        return if secret_value.to_s.empty? # return nil when the value is empty

        secret_value.to_s.scan("\n").empty?
      end

      def success_data
        {
          record: metadata_attributes,
          details: ancillary_attributes,
        }
      end

      private

      def _metadata_attributes
        # Start with safe receipt attributes
        attributes = receipt.safe_dump

        # Only include the secret's identifying key when necessary
        attributes[:secret_identifier] = secret_identifier if show_secret

        # Add additional attributes not included in safe dump
        attributes.merge!(
          {
            secret_state: secret_state, # can be nil (e.g. if secret is consumed)
            natural_expiration: natural_expiration,
            expiration: expiration,
            expiration_in_seconds: expiration_in_seconds,
            share_path: share_path,
            burn_path: burn_path,
            receipt_path: receipt_path,
            metadata_path: metadata_path, # maintain public API
            share_url: share_url,
            receipt_url: receipt_url,
            metadata_url: metadata_url, # maintain public API
            burn_url: burn_url,
          },
        )

        attributes
      end

      def ancillary_attributes
        {
          type: 'record',
          display_lines: display_lines,
          no_cache: no_cache,
          secret_realttl: secret_realttl,
          view_count: view_count,
          has_passphrase: has_passphrase,
          can_decrypt: can_decrypt,
          secret_value: secret_value,
          show_secret: show_secret,
          show_secret_link: show_secret_link,
          show_metadata_link: show_metadata_link,
          show_metadata: show_metadata,
          show_recipients: show_recipients,
        }
      end

      def process_uris
        @share_path    = build_path(:secret, secret_identifier)
        @burn_path     = build_path(:private, receipt_identifier, 'burn')
        @receipt_path  = build_path(:private, receipt_identifier)
        @metadata_path = @receipt_path # maintain public API
        @share_url     = build_url(share_domain, @share_path)
        @receipt_url   = build_url(baseuri, @receipt_path)
        @metadata_url  = @receipt_url # maintain public API
        @burn_url      = build_url(baseuri, @burn_path)
        @display_lines = calculate_display_lines
      end

      def calculate_display_lines
        v   = secret_value.to_s
        ret = ((80 + v.size) / 80) + v.scan("\n").size + 3
        ret > 30 ? 30 : ret
      end
    end
  end
end
