# frozen_string_literal: true

#
# apps/web/auth/config/hooks/session_integration.rb
#
# This file defines the Rodauth hooks for integrating Rodauth's session
# management with the broader application session. It handles syncing
# user data into the session on login and logging events.
#

module Auth
  module Config
    module Hooks
      module SessionIntegration
        #
        # Handlers
        #
        # This module contains the pure business logic for session integration.
        #
        module Handlers
          # Syncs the Rodauth session with the application's session format after a
          # successful login. This involves creating or updating customer records
          # and populating the session with necessary user data.
          #
          # @param account [Hash] The Rodauth account hash.
          # @param account_id [Integer] The ID of the Rodauth account.
          # @param session [Hash] The Rack session.
          # @param request [Rack::Request] The request object.
          #
          def self.sync_session_after_login(account, account_id, session, request)
            OT.info "[session-integration] Syncing session after login for account ID: #{account_id}"

            # --- 1. Clear Rate Limiting ---
            # On successful login, remove any rate limiting keys associated with the email.
            rate_limit_key = "login_attempts:#{account[:email]}"
            Familia.dbclient.del(rate_limit_key)

            # --- 2. Load or Create Customer Record ---
            # Find the associated Onetime::Customer record. If it doesn't exist,
            # create one to ensure data consistency.
            customer   = Onetime::Customer.find_by_extid(account[:external_id]) if account[:external_id]
            customer ||= Onetime::Customer.find_by_email(account[:email])

            unless customer
              OT.info '[session-integration] Customer not found, creating from Rodauth account.'
              customer = Onetime::Customer.create!(
                email: account[:email],
                role: 'customer',
                verified: account[:status_id] == 2 ? '1' : '0', # Rodauth status 2 is 'verified'
              )

              # Link the new customer record to the Rodauth account via external_id.
              Auth::Config::Database.connection[:accounts]
                .where(id: account_id)
                .update(external_id: customer.extid)

              OT.info "[session-integration] Created Customer: #{customer.custid} with extid: #{customer.extid}"
            end

            # --- 3. Populate Application Session ---
            # Write essential user and session data into the main application session.
            OT.info "[session-integration] Populating session for customer: #{customer&.custid}"

            session['authenticated']       = true
            session['authenticated_at']    = Familia.now.to_i
            session['account_id'] = account_id
            session['external_id'] = account[:external_id]

            if customer
              session['external_id'] = customer.extid
              session['email']       = customer.email
              session['role']        = customer.role
              session['locale']      = customer.locale || 'en'
            else
              # Fallback for safety, though customer should always exist at this point.
              session['email'] = account[:email]
              session['role']  = 'customer'
            end

            # --- 4. Track Request Metadata ---
            session['ip_address'] = request.ip
            session['user_agent'] = request.user_agent

            OT.info "[session-integration] Session synced successfully for #{session['email']}"
          end
        end

        #
        # Configuration
        #
        # This method returns a proc that Rodauth will execute to configure the
        # session integration hooks.
        #
        def self.configure
          proc do
            #
            # Hook: After Login
            #
            # This hook is triggered after a user successfully authenticates. It's
            # the primary integration point for syncing the application session.
            #
            after_login do
              OT.info "[auth] User logged in: #{account[:email]}"

              # Check if user is in partially authenticated state (has password but needs MFA)
              # Rodauth's two_factor_base provides this method automatically
              if two_factor_partially_authenticated?
                OT.info "[auth] MFA required for #{account[:email]}, deferring full session sync"
                # Only set minimal session data, full sync happens after MFA
                session['account_id'] = account_id
                session['email'] = account[:email]
                session['mfa_pending'] = true
              else
                OT.info "[auth] No MFA required or MFA completed, syncing session"
                Onetime::ErrorHandler.safe_execute('sync_session_after_login',
                  account_id: account_id,
                  email: account[:email],
                ) do
                  Handlers.sync_session_after_login(account, account_id, session, request)
                end
              end
            end

            #
            # Hook: After OTP Authentication
            #
            # This hook is triggered after successful two-factor (OTP) authentication.
            # Complete the full session sync that was deferred during login.
            #
            after_otp_auth do
              OT.info "[auth] OTP authentication successful for: #{account[:email]}"

              if session['mfa_pending']
                OT.info "[auth] Completing deferred session sync after MFA"
                Onetime::ErrorHandler.safe_execute('sync_session_after_mfa',
                  account_id: account_id,
                  email: account[:email],
                ) do
                  Handlers.sync_session_after_login(account, account_id, session, request)
                  session.delete('mfa_pending')
                end
              end
            end

            #
            # Hook: Before Logout
            #
            # This hook is triggered just before the session is destroyed on logout.
            #
            before_logout do
              OT.info "[auth] User logging out: #{session['email'] || 'unknown'}"
            end

            #
            # Hook: After Logout
            #
            # This hook is triggered after the user has been logged out.
            #
            after_logout do
              OT.info '[auth] Logout complete'
            end
          end
        end
      end
    end
  end
end
