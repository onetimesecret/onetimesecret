# apps/api/colonel/logic/colonel/set_banner.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/banner'

module ColonelAPI
  module Logic
    module Colonel
      # Publish / update the global broadcast banner (Colonel).
      #
      # Thin adapter over {Onetime::Operations::SetBanner} — the single, audited
      # implementation of the set verb (epic #41). This class keeps only the HTTP
      # concerns (param extraction + length/TTL validation); the op owns the Redis
      # write, the runtime refresh, and the AdminAuditEvent (CONTRACT 4).
      #
      # The banner is user-facing globally, so we bound its length here (the note
      # in the ticket). The content is stored VERBATIM (raw HTML) — NOT run through
      # sanitize_plain_text — so the stored value stays bit-for-bit identical to
      # what `bin/ots banner set` wrote; the frontend sanitizes to <a> tags on
      # render (GlobalBroadcast.vue's DOMPurify pass).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class SetBanner < ColonelAPI::Logic::Base
        # Hard cap on published banner length. A UI/HTTP guardrail only — the op
        # and the CLI impose no length limit (the CLI stays bit-for-bit unlimited).
        # Kept as a constant (not a config key) so no new config surface is added.
        MAX_CONTENT_LENGTH = 2000

        attr_reader :content, :expiration, :result

        def process_params
          # Store raw HTML verbatim (only trim surrounding whitespace, matching the
          # CLI's `--file` strip). Do NOT sanitize here — parity with the CLI.
          @content = params['content'].to_s.strip

          ttl_param = params['ttl']
          @expiration = ttl_param.to_i unless ttl_param.nil? || ttl_param.to_s.strip.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Banner content is required', field: :content) if content.empty?

          if content.length > MAX_CONTENT_LENGTH
            raise_form_error(
              "Banner content exceeds the #{MAX_CONTENT_LENGTH}-character limit",
              field: :content
            )
          end

          if !expiration.nil? && expiration.negative?
            raise_form_error('TTL must be a positive number of seconds', field: :ttl)
          end
        end

        def process
          # A zero / absent TTL means "persistent" (nil) to the op; only a positive
          # value becomes an auto-expiry. actor is the acting colonel's PUBLIC id.
          @result = Onetime::Operations::SetBanner.new(
            content: content,
            ttl: (expiration if !expiration.nil? && expiration.positive?),
            actor: cust.extid,
          ).call

          success_data
        end

        def success_data
          {
            record: {
              content: result.content,
              ttl: result.ttl,
              active: true,
            },
            details: {
              message: 'Broadcast banner published',
            },
          }
        end
      end
    end
  end
end
