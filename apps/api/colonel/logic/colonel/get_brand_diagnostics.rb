# apps/api/colonel/logic/colonel/get_brand_diagnostics.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Get Brand-Pack Diagnostics
      #
      # @api Returns read-only brand-pack resolution diagnostics for the running
      #   instance: raw BRAND_* env, the frozen boot config snapshot, brand-pack
      #   search roots, the live-resolved overlay dir, whether it fell back to the
      #   default pack, on-disk manifest keys, a boot-vs-live mismatch flag
      #   (the mount-race detector), and the overlay assets present on disk.
      #   Mutates nothing. Requires colonel role. (#3822)
      class GetBrandDiagnostics < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'brandDiagnostics' }.freeze

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          success_data
        end

        # Thin adapter over Onetime.brand_pack_diagnostics (lib/onetime.rb) — the
        # single source of truth, shared with `bin/ots config brand`. Overrides
        # success_data WITHOUT super so the Base custid->user_id transform (which
        # this payload has no use for) never runs; the diagnostics hash is emitted
        # verbatim under `details`.
        def success_data
          {
            record: {},
            details: Onetime.brand_pack_diagnostics,
          }
        end
      end
    end
  end
end
