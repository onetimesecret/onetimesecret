# apps/api/account/logic/account/confirm_email_change.rb
#
# frozen_string_literal: true

require_relative '../base'

module AccountAPI::Logic
  module Account
    using Familia::Refinements::TimeLiterals

    class ConfirmEmailChange < AccountAPI::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :secret

      def process_params
        @token  = params['token'].to_s.strip
        @secret = Onetime::Secret.find_by_identifier(@token) unless @token.empty?
      end

      def raise_concerns
        raise OT::MissingSecret if @secret.nil?
        raise OT::MissingSecret unless @secret.exists?
        raise OT::MissingSecret if @secret.custid.to_s == 'anon'

        raise_form_error 'This link has expired', error_type: 'expired' unless @secret.verification?

        @owner = @secret.load_owner
        raise_form_error 'Invalid confirmation link', error_type: 'invalid' if @owner.nil?

        # Verify the pending_email_change matches
        unless Rack::Utils.secure_compare(@owner.pending_email_change.to_s, @secret.identifier)
          raise_form_error 'This confirmation link is no longer valid', error_type: 'invalid'
        end
      end

      def process
        old_email = @owner.email
        new_email = sanitize_email(@secret.decrypted_secret_value)

        if new_email.empty?
          raise_form_error 'Unable to determine new email address', error_type: 'system_error'
        end

        # Check the new email hasn't been taken since the request was made
        if Onetime::Customer.email_exists?(new_email)
          raise_form_error 'This email is no longer available', error_type: 'unavailable'
        end

        OT.info "[confirm-email-change] Confirming email change cid/#{@owner.objid} old/#{OT::Utils.obscure_email(old_email)} new/#{OT::Utils.obscure_email(new_email)}"

        # Update Auth DB first (transactional) so failure doesn't leave Redis in
        # an inconsistent state. If this raises, Redis is untouched.
        update_auth_database(@owner, new_email) if Onetime.auth_config.full_enabled?

        # Update email field, then update the global index
        # (update_in_class_email_index reads the current email field for the new value)
        @owner.email = new_email
        @owner.update_in_class_email_index(old_email)
        @owner.save

        # Update org-scoped email index if org context exists
        update_org_email_index(@owner, old_email)

        # Clear the pending change marker
        @owner.pending_email_change.delete!

        # Destroy the verification secret
        @secret.destroy!

        # Invalidate all sessions for this customer
        invalidate_sessions(@owner)

        OT.info "[confirm-email-change] Email change confirmed cid/#{@owner.objid} new/#{OT::Utils.obscure_email(new_email)}"

        success_data
      end

      def success_data
        { confirmed: true, redirect: '/signin' }
      end

      private

      def update_org_email_index(customer, old_email)
        orgs = customer.organization_instances.to_a
        orgs.each do |org|
          customer.update_in_organization_email_index(org, old_email)
        end
      rescue StandardError => ex
        OT.le "[confirm-email-change] Org index update failed cid/#{customer.objid}: #{ex.message}"
        OT.le ex.backtrace.first(5).join("\n")
      end

      def find_auth_account(customer)
        db = Auth::Database.connection
        return nil, nil unless db

        account = db[:accounts].where(external_id: customer.extid).first
        [db, account]
      end

      def update_auth_database(customer, new_email)
        db, account = find_auth_account(customer)
        return unless account

        db[:accounts].where(id: account[:id]).update(email: new_email)

        OT.info "[confirm-email-change] Auth database updated cid/#{customer.objid}"
      rescue StandardError => ex
        OT.le "[confirm-email-change] Auth database update failed: #{ex.message}"
        raise_form_error 'Email change could not be completed', error_type: 'system_error'
      end

      def invalidate_sessions(customer)
        # Delete all active session rows from the auth database.
        # On next request, Rodauth's currently_active_session? finds no
        # matching row and force-clears the stale Rack session.
        if Onetime.auth_config.full_enabled?
          db, account = find_auth_account(customer)
          if account
            count = db[:account_active_session_keys]
              .where(account_id: account[:id])
              .delete
            OT.info "[confirm-email-change] Invalidated #{count} auth DB session(s) for cid/#{customer.objid}"
          end
        end

        # Delete all Redis session keys belonging to this customer.
        # Sessions are stored as session:<hex_id> with HMAC-signed JSON
        # containing an external_id field that identifies the owner.
        delete_redis_sessions(customer)

        # Also clear the current request's session if present
        sess.clear if sess
      rescue StandardError => ex
        OT.le "[confirm-email-change] Session invalidation error: #{ex.message}"
      end

      # Scan Redis for all session keys belonging to the given customer
      # and delete them. Uses SCAN to avoid blocking Redis on large keyspaces.
      #
      # Session values are stored as "base64(json)--hmac". We decode and
      # check whether external_id matches the customer's extid.
      def delete_redis_sessions(customer)
        extid = customer.extid
        return if extid.nil? || extid.empty?

        dbclient = Familia.dbclient
        deleted  = 0

        dbclient.scan_each(match: 'session:*') do |key|
          session_extid = extract_session_extid(dbclient, key)
          next unless session_extid == extid

          dbclient.del(key)
          deleted += 1
        end

        OT.info "[confirm-email-change] Deleted #{deleted} Redis session(s) for cid/#{customer.objid}"
      rescue StandardError => ex
        OT.le "[confirm-email-change] Redis session cleanup error: #{ex.message}"
      end

      # Extract the external_id from a stored session value without
      # verifying the HMAC (we are deleting, not trusting the data).
      # Returns nil if the value cannot be decoded.
      def extract_session_extid(dbclient, key)
        raw = dbclient.get(key)
        return nil unless raw

        data, _hmac = raw.split('--', 2)
        return nil unless data

        decoded = Base64.decode64(data)
        parsed  = Familia::JsonSerializer.parse(decoded)
        parsed['external_id']
      rescue StandardError
        nil
      end
    end
  end
end
