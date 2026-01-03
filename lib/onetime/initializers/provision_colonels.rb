# lib/onetime/initializers/provision_colonels.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # ProvisionColonels initializer
    #
    # Auto-provisions colonel accounts from site.authentication.colonels config.
    # Handles both simple and full authentication modes.
    #
    # Simple Mode:
    # - Creates Customer records in Redis with role=colonel
    # - Generates secure random passwords (logged for admin distribution)
    # - Auto-verifies accounts
    #
    # Full Mode:
    # - Creates Customer in maindb (Redis)
    # - Creates account in authdb (SQL via Rodauth)
    # - Links via external_id
    # - Generates secure random passwords (logged for admin distribution)
    # - Auto-verifies in both systems
    #
    # Edge Cases:
    # - Skips if authentication is disabled
    # - Skips if colonels list is empty
    # - Logs warnings for existing accounts with mismatched roles
    # - Gracefully handles individual failures without failing boot
    #
    class ProvisionColonels < Onetime::Boot::Initializer
      @depends_on = [:database]
      @provides   = [:colonel_accounts]
      @optional   = true

      def execute(_context)
        # Skip if authentication is disabled
        auth_config = OT.conf.dig('site', 'authentication') || {}
        unless auth_config['enabled']
          OT.ld '[init] Skipping colonel provisioning (authentication disabled)'
          return
        end

        # Get colonels list from config
        colonels = auth_config['colonels'] || []
        if colonels.empty? || colonels == [false]
          OT.ld '[init] No colonels configured for auto-provisioning'
          return
        end

        # Filter out placeholder/example values
        colonels = colonels.reject { |email| email.to_s.include?('CHANGEME') || email.to_s.include?('example.com') }

        if colonels.empty?
          OT.ld '[init] No valid colonels after filtering placeholders'
          return
        end

        auth_mode = Onetime.auth_config.mode
        OT.li "[init] Provisioning #{colonels.size} colonel account(s) (auth_mode: #{auth_mode})"

        colonels.each do |email|
          provision_colonel(email, auth_mode)
        rescue StandardError => ex
          # Log but don't fail boot
          OT.le "[init] Failed to provision colonel #{OT::Utils.obscure_email(email)}: #{ex.message}"
          OT.ld ex.backtrace&.join("\n") if OT.debug?
        end
      end

      private

      def provision_colonel(email, auth_mode)
        case auth_mode
        when 'full'
          provision_colonel_full_mode(email)
        when 'simple'
          provision_colonel_simple_mode(email)
        else
          OT.le "[init] Unknown auth mode: #{auth_mode}"
        end
      end

      # Simple mode: Redis-only customer creation
      def provision_colonel_simple_mode(email)
        obscured = OT::Utils.obscure_email(email)

        # Check if customer exists
        if Onetime::Customer.email_exists?(email)
          customer = Onetime::Customer.find_by_email(email)

          # Verify role matches
          if customer.role.to_s != 'colonel'
            OT.lw "[init] Customer #{obscured} exists but role is '#{customer.role}' (expected 'colonel'). Manual fix needed."
          else
            OT.ld "[init] Colonel #{obscured} already provisioned"
          end

          return
        end

        # Create new customer with colonel role
        password = generate_secure_password

        customer = Onetime::Customer.create!(
          email: email,
          role: 'colonel',
          verified: 'true',
          verified_by: 'auto_provision',
        )

        # Set password
        customer.update_passphrase(password, algorithm: :argon2)
        customer.save

        OT.li "[init] ✓ Provisioned colonel #{obscured}"
        log_password(email, password)
      end

      # Full mode: Redis + SQL account creation
      def provision_colonel_full_mode(email)
        obscured = OT::Utils.obscure_email(email)

        # Get auth database connection
        authdb = Auth::Database.connection
        unless authdb
          OT.le '[init] Auth database not available for colonel provisioning'
          return
        end

        # Check Redis for existing customer
        redis_exists = Onetime::Customer.email_exists?(email)

        # Check SQL for existing account
        sql_account = authdb[:accounts].where(email: email).first

        # Case 1: Exists in both systems
        if redis_exists && sql_account
          customer = Onetime::Customer.find_by_email(email)

          if customer.role.to_s != 'colonel'
            OT.lw "[init] Customer #{obscured} exists but role is '#{customer.role}' (expected 'colonel'). Manual fix needed."
          else
            OT.ld "[init] Colonel #{obscured} already provisioned in both systems"
          end

          return
        end

        # Case 2: Exists in Redis but not SQL (partial state)
        if redis_exists && !sql_account
          customer = Onetime::Customer.find_by_email(email)
          password = generate_secure_password

          # Create SQL account and link
          create_rodauth_account(authdb, email, password, customer.extid)

          if customer.role.to_s != 'colonel'
            customer.role = 'colonel'
            customer.save
            OT.lw "[init] Updated #{obscured} role to colonel"
          end

          OT.li "[init] ✓ Provisioned colonel #{obscured} (created authdb account)"
          log_password(email, password)
          return
        end

        # Case 3: Exists in SQL but not Redis (partial state)
        if !redis_exists && sql_account
          password = generate_secure_password

          # Create Redis customer
          customer = Onetime::Customer.create!(
            email: email,
            role: 'colonel',
            verified: 'true',
            verified_by: 'auto_provision',
          )
          customer.update_passphrase(password, algorithm: :argon2)
          customer.save

          # Link to existing SQL account
          authdb[:accounts].where(id: sql_account[:id]).update(external_id: customer.extid)

          # Update SQL account password
          password_hash = ::Argon2::Password.create(password)
          authdb[:accounts].where(id: sql_account[:id]).update(password_hash: password_hash)

          OT.li "[init] ✓ Provisioned colonel #{obscured} (created maindb customer)"
          log_password(email, password)
          return
        end

        # Case 4: New account (doesn't exist in either system)
        password = generate_secure_password

        # Create Redis customer first
        customer = Onetime::Customer.create!(
          email: email,
          role: 'colonel',
          verified: 'true',
          verified_by: 'auto_provision',
        )
        customer.update_passphrase(password, algorithm: :argon2)
        customer.save

        # Create SQL account and link
        create_rodauth_account(authdb, email, password, customer.extid)

        OT.li "[init] ✓ Provisioned new colonel #{obscured}"
        log_password(email, password)
      end

      # Create Rodauth account in SQL database
      def create_rodauth_account(db, email, password, external_id)
        password_hash = ::Argon2::Password.create(password)

        db[:accounts].insert(
          email: email,
          password_hash: password_hash,
          status_id: 2, # Verified (status_id=1 is unverified, 2 is verified per Rodauth convention)
          external_id: external_id,
        )
      rescue Sequel::UniqueConstraintViolation
        # Account already exists, just link it
        account = db[:accounts].where(email: email).first
        db[:accounts].where(id: account[:id]).update(external_id: external_id) if account
      end

      # Generate cryptographically secure random password
      def generate_secure_password
        # 20 characters = ~119 bits entropy (log2(62^20))
        SecureRandom.alphanumeric(20)
      end

      # Log generated password for admin distribution
      def log_password(email, password)
        obscured = OT::Utils.obscure_email(email)
        OT.li "[init] 🔑 Colonel password for #{obscured}: #{password}"
        OT.li '[init] ⚠️  Save this password - it will not be displayed again'
      end
    end
  end
end
