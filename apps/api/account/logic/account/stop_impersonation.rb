# apps/api/account/logic/account/stop_impersonation.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/session/impersonation'
require 'auth/operations/customers/stop_impersonation'

module AccountAPI
  module Logic
    module Account
      # End the colonel impersonation running on this session.
      #
      # POST /api/account/impersonation/stop
      #
      # ## Why this lives on the customer surface
      #
      # It is the only mutating endpoint an impersonated session may call, and
      # it cannot live where the rest of impersonation lives:
      #
      #   - `/api/colonel/*` is blocked outright by
      #     Middleware::ImpersonationContext, and AdminNetworkIsolation can
      #     404 it by host/CIDR on top of that;
      #   - a `role=colonel` route option would fail, because from the moment
      #     the marker exists the authenticated user IS the target — a
      #     customer. That is the whole point of the overlay, and it is
      #     precisely why the stop button cannot be an admin route.
      #
      # The Account API is the right home: "site-only account management
      # endpoints", session-authenticated, mounted at `/api/account` on the
      # same host set as everything else (Registry#generate_rack_url_map keys
      # URLMap by PATH only), and outside AdminNetworkIsolation's
      # `admin_surface?` (which matches only `/colonel*` and `/api/colonel*`).
      #
      # So: `auth=sessionauth`, no `role=`, and the authorization is done HERE
      # against the PRINCIPAL rather than against `cust` (which is the target).
      #
      # ## 404, not 403
      #
      # A session with no marker — or one whose principal is not a verified
      # colonel — is told the route does not exist. A 403 would confirm to any
      # logged-in customer that an impersonation endpoint is mounted and
      # reachable; there is no reason to publish that.
      class StopImpersonation < AccountAPI::Logic::Base
        attr_reader :principal, :marker, :result

        def process_params
          # No input. The session IS the argument, deliberately: an
          # impersonation_id parameter would only invite a caller to try
          # stopping one that is not theirs.
        end

        def raise_concerns
          raise_not_found('Not Found') unless authorized?
        end

        def process
          @result = Auth::Operations::Customers::StopImpersonation.new(
            session: sess,
            actor: principal.extid,
          ).call

          # Re-stamp the cached role from the PRINCIPAL. SessionHelpers#has_role?
          # answers from this cache without loading a Customer, and the
          # impersonation write-guard in SessionHelpers#load_current_customer
          # left it alone for the duration — so this is belt-and-braces against
          # any other path that might have touched it while the overlay was up.
          sess['role'] = principal.role if sess.respond_to?(:[]=)

          success_data
        end

        def success_data
          {
            record: {
              stopped: result.status == :stopped,
              target_extid: result.target_extid,
              # Back to where the operator was: the target's console detail
              # page (src/apps/admin/routes.ts — `/colonel/customers/:id`,
              # where :id is the extid).
              redirect: "/colonel/customers/#{result.target_extid}",
            },
            details: {},
          }
        end

        private

        # The PRINCIPAL must be a verified colonel AND a marker must be live.
        # Resolved from the session, never from `cust`: during an impersonation
        # `cust` is the target customer.
        def authorized?
          return false unless sess.respond_to?(:[])

          @marker = Onetime::SessionImpersonation.active(sess)
          return false unless marker

          external_id = sess['external_id'].to_s
          return false if external_id.empty?

          @principal = Onetime::Customer.load_by_extid_or_email(external_id)
          return false unless principal

          principal.role?('colonel') && principal.verified?
        end
      end
    end
  end
end
