# apps/api/account/logic/account/confirm_email_change.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../lib/onetime/jobs/publisher'
require 'onetime/logic/sso_only_gating'

module AccountAPI::Logic
  module Account
    using Familia::Refinements::TimeLiterals

    class ConfirmEmailChange < AccountAPI::Logic::Base
      include Onetime::LoggerMethods
      include Onetime::Logic::SsoOnlyGating

      attr_reader :secret

      def process_params
        @token  = params['token'].to_s.strip
        @secret = Onetime::Secret.find_by_identifier(@token) unless @token.empty?
      end

      def raise_concerns
        require_non_sso_only!

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

        # Send confirmation notification to the OLD email (the email has now changed)
        begin
          Onetime::Jobs::Publisher.enqueue_email(
            :email_changed,
            {
              old_email: old_email,
              new_email: new_email,
              locale: locale || @owner.locale || OT.default_locale,
            },
            fallback: :async_thread,
          )
        rescue StandardError => ex
          OT.le "[confirm-email-change] Failed to send email-changed notification: #{ex.message}"
        end

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
      # Session values are stored as "base64(encrypted)--hmac". We verify
      # the HMAC, decrypt, and check whether external_id matches the
      # customer's extid.
      def delete_redis_sessions(customer)
        extid = customer.extid
        return if extid.nil? || extid.empty?

        dbclient = Familia.dbclient
        deleted  = 0

        # Derive the same HMAC and encryption keys that Onetime::Session uses,
        # so we can verify and decrypt session data before trusting it.
        session_secret     = resolve_session_secret
        hmac_key           = Onetime::KeyDerivation.derive_session_subkey(session_secret, 'hmac')
        encryption_key_raw = [Onetime::KeyDerivation.derive_session_subkey(session_secret, 'encryption')].pack('H*')

        dbclient.scan_each(match: 'session:*') do |key|
          session_extid = extract_session_extid(dbclient, key, hmac_key, encryption_key_raw)
          next unless session_extid == extid

          dbclient.del(key)
          deleted += 1
        end

        OT.info "[confirm-email-change] Deleted #{deleted} Redis session(s) for cid/#{customer.objid}"
      rescue StandardError => ex
        OT.le "[confirm-email-change] Redis session cleanup error: #{ex.message}"
      end

      # Resolve the session secret using the same fallback chain as
      # Onetime::Session#initialize: ENV['SESSION_SECRET'] then site secret.
      def resolve_session_secret
        secret = ENV.fetch('SESSION_SECRET', nil)
        return secret if secret.is_a?(String) && !secret.empty?

        OT.conf.dig('site', 'secret')
      end

      # Extract the external_id from a stored session value after verifying
      # the HMAC signature and decrypting the payload. Returns nil if the
      # value cannot be verified or decoded.
      def extract_session_extid(dbclient, key, hmac_key, encryption_key_raw)
        raw = dbclient.get(key)
        return nil unless raw

        data, hmac = raw.split('--', 2)
        return nil unless data && hmac

        # Verify HMAC to ensure the session data has not been tampered with
        expected_hmac = OpenSSL::HMAC.hexdigest('SHA256', hmac_key, data)
        return nil unless hmac.bytesize == expected_hmac.bytesize
        return nil unless Rack::Utils.secure_compare(expected_hmac, hmac)

        # Decode and decrypt the session payload
        encrypted_data = Base64.strict_decode64(data)
        return nil if encrypted_data.nil? || encrypted_data.bytesize < 28

        cipher          = OpenSSL::Cipher.new('aes-256-gcm')
        cipher.decrypt
        cipher.key      = encryption_key_raw
        cipher.iv       = encrypted_data[0, 12]
        cipher.auth_tag = encrypted_data[12, 16]
        decrypted       = cipher.update(encrypted_data[28..]) + cipher.final

        parsed = Familia::JsonSerializer.parse(decrypted)
        parsed['external_id']
      rescue StandardError
        nil
      end
    end
  end
end
