# apps/web/core/logic/authentication/authenticate_session.rb
#
# frozen_string_literal: true

require 'onetime/logic/base'

module Core::Logic
  module Authentication
    using Familia::Refinements::TimeLiterals

    class AuthenticateSession < Onetime::Logic::Base
      include Onetime::LoggerMethods

      attr_reader :objid, :stay, :greenlighted, :session_ttl, :potential_email_address

      # cust is only populated if the passphrase matches
      def process_params
        # NOTE: The parameter names should match what rodauth uses.
        @potential_email_address = params['login'].to_s.downcase.strip
        @passwd                  = self.class.normalize_password(params['password'])
        @stay                    = true # Keep sessions alive by default
        @session_ttl             = (stay ? 30.days : 20.minutes).to_i

        potential = Onetime::Customer.find_by_email(potential_email_address)

        return unless potential

        passwd_matches = potential.passphrase?(@passwd)
        @cust          = potential if passwd_matches
        @objid         = @cust.objid if @cust

        # Transparent password hash migration: rehash bcrypt passwords to argon2
        # on successful login while we have the plaintext password available.
        migrate_password_hash_if_needed(potential, @passwd) if passwd_matches
      end

      # Migrate legacy bcrypt password hashes to argon2id on successful login.
      # This provides a gradual, transparent migration path without forcing
      # password resets or requiring user action.
      #
      # @param customer [Onetime::Customer] The authenticated customer
      # @param password [String] The verified plaintext password
      def migrate_password_hash_if_needed(customer, password)
        return if customer.argon2_hash?(customer.passphrase)

        customer.update_passphrase!(password)
        auth_logger.info 'Password hash migrated to argon2', {
          user_id: customer.objid,
          email: customer.obscure_email,
          action: 'password_hash_migration',
        }
      rescue StandardError => ex
        # Log the error but don't fail the login - the bcrypt hash remains
        # intact and will be migrated on the next successful login attempt.
        auth_logger.error 'Password hash migration failed', {
          user_id: customer.objid,
          email: customer.obscure_email,
          error: ex.message,
          action: 'password_hash_migration_failed',
        }
      end

      def raise_concerns
        return unless @cust.nil?

        @cust ||= Onetime::Customer.anonymous
        raise_form_error 'Invalid email or password', field: 'email', error_type: 'invalid'
      end

      def process
        unless success?
          auth_logger.warn 'Login failed', {
            email: cust.obscure_email,
            role: cust.role,
            session_id: sess&.id,
            ip: @strategy_result.metadata[:ip],
            reason: :invalid_credentials,
          }

          raise_form_error 'Invalid email or password', field: 'email', error_type: 'invalid'
        end

        if cust.pending?
          auth_logger.info 'Login pending customer verification', {
            customer_id: cust.objid,
            email: cust.obscure_email,
            role: cust.role,
            session_id: sess&.id,
            status: :pending,
          }

          # Do not send an email to a someone that's just logged-in with a basic
          # authmode account where verified=false and autoverify is disabled. With
          # autoverify disabled, the registration flow sets verified=true and
          # skips the email verification process. However, if the site admin
          # has manually set verified=false on the account (e.g. for moderation
          # purposes), we don't want to spam them with verification emails
          # every time they log in. This scenario could also happen if the
          # site configuration changes after users have already signed up
          # but not yet verified.
          autoverify = OT.conf.dig('site', 'authentication', 'autoverify')
          unless autoverify.to_s == 'true'
            # When autoverify is enabled, proactively help pending accounts
            # get verified by resending the verification email (valid for 24h)
            auth_logger.info 'Resending verification email (autoverify mode)', {
              customer_id: cust.objid,
              email: cust.obscure_email,
            }

            send_verification_email nil

            verification_msg = I18n.t('web.COMMON.verification_sent_to',
              locale: locale,
              default: 'Verification sent to',
            )
            msg              = "#{verification_msg} #{cust.objid}."
            set_info_message(msg)
          end

          return success_data
        end

        @greenlighted = true

        # Clear old session data to prevent session fixation
        sess.clear

        # Set session authentication data
        sess['external_id']      = cust.extid
        sess['authenticated']    = true
        sess['authenticated_at'] = Familia.now.to_i
        cust.save

        colonels  = OT.conf.dig('site', 'authentication', 'colonels') || []
        cust.role = if colonels.member?(cust.email)
          :colonel
        else
          :customer
        end

        auth_logger.info 'Login successful', {
          user_id: cust.objid,
          email: cust.obscure_email,
          role: cust.role,
          session_id: sess.id,
          ip: @strategy_result.metadata[:ip],
          stay: stay,
          session_ttl: session_ttl,
        }

        success_data
      end

      def success_data
        { objid: cust.objid, role: cust.role }
      end

      def success?
        !cust&.anonymous? && (cust.passphrase?(@passwd) || @colonel&.passphrase?(@passwd))
      end

      private

      def form_fields
        { objid: objid }
      end
    end
  end
end
