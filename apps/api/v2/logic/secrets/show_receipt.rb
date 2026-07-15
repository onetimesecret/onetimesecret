# apps/api/v2/logic/secrets/show_receipt.rb
#
# frozen_string_literal: true

module V2::Logic
  module Secrets
    using Familia::Refinements::TimeLiterals

    # Show Receipt
    #
    # @api Retrieves the receipt (metadata) for a previously created secret.
    #   Returns the receipt's state, share and burn URLs, expiration details,
    #   and recipient information. For generated secrets viewed shortly after
    #   creation, the generated value may be included. The receipt tracks
    #   whether the associated secret has been viewed, burned, or expired.
    class ShowReceipt < V2::Logic::Base
      include Onetime::Logic::GuestRouteGating

      SCHEMAS = { response: 'receipt' }.freeze

      # Working variables
      attr_reader :identifier, :receipt, :secret
      # Template variables
      attr_reader :receipt_identifier,
        :receipt_shortid,
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
        :first_access,
        :last_access,
        :has_passphrase,
        :can_decrypt,
        :secret_value,
        :show_secret,
        :show_secret_link,
        :show_receipt_link,
        :receipt_attributes,
        :show_receipt,
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
        require_guest_route_enabled!(:receipt)
        require_entitlement!('api_access')
        raise OT::MissingSecret, "identifier: #{identifier}" if receipt.nil?
      end

      def process # rubocop:disable Metrics/MethodLength,Metrics/PerceivedComplexity
        @secret = @receipt.load_secret

        @receipt_identifier = receipt.identifier
        @receipt_shortid    = receipt.shortid
        @secret_identifier  = receipt.secret_identifier
        @secret_shortid     = receipt.secret_shortid

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

        # Access telemetry from the receipt's timeline (#3633). Derived here
        # regardless of whether the secret still exists: the timeline outlives
        # the secret, and "was it accessed before it was revealed/burned?" is
        # exactly what the creator wants to know afterwards.
        @view_count   = receipt.access_count
        @first_access = receipt.first_access_at
        @last_access  = receipt.last_access_at

        # Reuse the instance already loaded at the top of process rather than
        # hitting Redis a second time; nothing in between mutates the secret.
        secret = @secret

        if secret.nil?

          burned_or_revealed = receipt.state?(:burned) || receipt.state?(:revealed) || receipt.state?(:received)

          if !burned_or_revealed && receipt.secret_expired?
            OT.le("[show_receipt] Receipt has expired secret. #{receipt.shortid}")
            receipt.expired!  # Sets secret_identifier to empty
            @secret_identifier = nil  # Clear local variable to prevent leaking
          elsif !burned_or_revealed
            OT.le("[show_receipt] Receipt is an orphan. #{receipt.shortid}")
            receipt.orphaned!  # Sets secret_identifier to empty
            @secret_identifier = nil  # Clear local variable to prevent leaking
          end

          # Check for both new 'revealed' state and legacy 'received' state
          @is_received  = receipt.state?(:revealed) || receipt.state?(:received)
          @is_burned    = receipt.state?(:burned)
          @is_expired   = receipt.state?(:expired)
          @is_orphaned  = receipt.state?(:orphaned)
          @is_destroyed = @is_burned || @is_received || @is_expired || @is_orphaned

          if is_destroyed && receipt.secret_identifier
            receipt.secret_identifier! nil
            @secret_identifier = nil  # Clear local variable to prevent leaking
          end
        else
          @secret_state   = secret.state
          @secret_realttl = secret.current_expiration

          if secret.viewable?
            @has_passphrase = !secret.passphrase.to_s.empty?
            @can_decrypt    = secret.can_decrypt?
            # If we can't decrypt the secret (i.e. if we can't access it) then
            # then we leave secret_value nil. We do this so that after creating
            # a secret we can show the received contents on the "/receipt/receipt_identifier"
            # page ONE TIME. Particularly for generated passwords which are not
            # shown any other time.
            #
            # Only the decrypted value of a generated password is shown, and
            # only to the FIRST load, and only within the display window.
            # Concealed (user-typed) secrets are never shown on the receipt page
            # — the user already knows the value.
            #
            # claim_secret_value_display! is the "one time" guarantee: it
            # atomically claims the display so a repeated or concurrent load
            # never re-reveals the value (#3633 retired the previewed! state
            # mutation that used to bound this, so this GET must not lean on a
            # state change). display_ttl now only bounds *when* the single
            # reveal may happen — a first visit after the window shows nothing —
            # rather than how many times. Claim last, so the window/kind checks
            # short-circuit before we consume the one-shot claim.
            if receipt.state?(:new)
              receipt_age   = Familia.now.to_i - receipt.created.to_i
              is_generated  = receipt.kind.to_s == 'generate'
              display_ttl   = OT.conf.dig('site', 'secret_options', 'generated_value_display_ttl').to_i
              within_window = display_ttl.positive? && receipt_age < display_ttl
              # C10 fast-fail: a mismatched SECRET can't decrypt anything, and
              # decrypt raises *after* claim_secret_value_display! burns the
              # one-shot slot — leaving the generated value permanently
              # unshowable. Gate the claim on verifier state (it is last in the
              # &&, so a mismatch short-circuits before the slot is consumed),
              # keeping the reveal intact per the non-destructive contract.
              if is_generated && within_window &&
                 Onetime.secret_verifier_state != :mismatch &&
                 receipt.claim_secret_value_display!
                OT.ld "[show_receipt] m:#{receipt_identifier} s:#{secret_identifier} One-time reveal of generated secret to creator (age: #{receipt_age}s)"
                @secret_value = secret.decrypted_secret_value
              end
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
        # Note: Check both new states (revealed) and legacy states (received).
        # previewed/viewed are backward-compat guards for pre-#3633 data only —
        # no GET path advances a receipt to those states anymore (the previewed!
        # mutation was retired), so live receipts never reach them via this page.
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
        @show_receipt_link = receipt.state?(:new)

        # Allow the receipt to be shown if it hasn't been previewed/viewed yet OR
        # if the current user owns it (regardless of its previewed/viewed state).
        #
        # It will be true if EITHER of these conditions are met:
        #   1. The receipt state is NOT 'previewed' or 'viewed', OR
        #   2. The current customer is the owner of the receipt
        #
        @show_receipt = !(receipt.state?(:previewed) || receipt.state?(:viewed)) || receipt.owner?(cust)

        # Recipient information is only displayed when the receipt is
        # visible and there are actually recipients to show.
        #
        # It will be true if BOTH of these conditions are met:
        #   1. The receipt should be shown (@show_receipt is true), AND
        #   2. There are recipients specified (@recipients is not empty)
        #
        @show_recipients = @show_receipt && !@recipients.empty?

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

        @receipt_attributes = _receipt_attributes

        # Loading the receipt page is a safe GET: it records a one-time
        # 'receipt_viewed' audit event but must NOT advance the secret's
        # lifecycle state (#3633). "previewed" now names the distinct event of
        # the creator opening their own secret *link* (recorded on the access
        # timeline via AccessTelemetry), not this metadata-page load -- so
        # viewing the receipt no longer flips receipt.state to 'previewed'. The
        # creator's live view/link is instead driven by the append-only access
        # timeline (view_count/first_access). record_receipt_view! is
        # idempotent, bounding the org trail against a hammered receipt page.
        receipt.record_receipt_view!

        success_data
      end

      def one_liner
        return if secret_value.to_s.empty? # return nil when the value is empty

        secret_value.to_s.scan("\n").empty?
      end

      def success_data
        {
          record: receipt_attributes,
          details: ancillary_attributes,
        }
      end

      private

      def _receipt_attributes
        # Start with safe receipt attributes
        attributes = receipt.safe_dump

        # Provenance gate: incoming secrets withhold the share link (and its
        # secret_identifier bearer key) from the creator. safe_dump already
        # withholds secret_identifier for these; keep the re-add and the
        # share_url/share_path merge below consistent with it.
        link_visible = receipt.shows_share_link?

        # Only include the secret's identifying key when necessary
        # Remove it from safe_dump and only add it back if show_secret is true
        # AND provenance permits sharing the link.
        if show_secret && link_visible
          attributes[:secret_identifier] = secret_identifier
        else
          attributes.delete(:secret_identifier)
        end

        # Add additional attributes not included in safe dump
        attributes.merge!(
          {
            secret_state: secret_state, # can be nil (e.g. if secret is consumed)
            natural_expiration: natural_expiration,
            # expiration is nil for a consumed/expired secret (no live secret to
            # expire); the V3 contract allows null. expiration_in_seconds is the
            # raw secret_ttl, which bypasses the receipt safe_dump cast — coerce
            # it here so a string-typed value can't trip the strict z.number()
            # contract and null the whole receipt (#3424).
            expiration: expiration,
            expiration_in_seconds: expiration_in_seconds.to_i,
            # share_path/share_url are the secret link; withheld (null) for
            # incoming provenance. burn/receipt paths stay — the creator still
            # manages the receipt. Null is the intended "link withheld" signal
            # (contract makes these nullable), not a defect (#3424).
            share_path: link_visible ? share_path : nil,
            burn_path: burn_path,
            receipt_path: receipt_path,
            metadata_path: metadata_path, # V2 backward-compat alias
            share_url: link_visible ? share_url : nil,
            receipt_url: receipt_url,
            metadata_url: metadata_url, # V2 backward-compat alias
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
          first_access: first_access,
          last_access: last_access,
          has_passphrase: has_passphrase || false,
          can_decrypt: can_decrypt || false,
          secret_value: secret_value,
          show_secret: show_secret,
          show_secret_link: show_secret_link,
          show_receipt_link: show_receipt_link,
          show_receipt: show_receipt,
          show_recipients: show_recipients,
        }
      end

      def process_uris
        @share_path    = build_path(:secret, secret_identifier)
        @burn_path     = build_path(:receipt, receipt_identifier, 'burn')
        @receipt_path  = build_path(:receipt, receipt_identifier)
        @metadata_path = @receipt_path # V2 backward-compat alias
        @share_url     = build_url(share_domain, @share_path)
        @receipt_url   = build_url(share_domain, @receipt_path)
        @metadata_url  = @receipt_url # V2 backward-compat alias
        @burn_url      = build_url(share_domain, @burn_path)
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
