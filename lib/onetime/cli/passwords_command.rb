# lib/onetime/cli/passwords_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # CLI command for password hash statistics and management.
    # Provides visibility into the bcrypt-to-argon2 migration progress.
    #
    # Usage:
    #   bin/ots passwords --stats    # Show hash algorithm distribution
    #
    class PasswordsCommand < Command
      desc 'Password hash statistics and management'

      option :stats, type: :boolean, default: false,
        desc: 'Show password hash algorithm distribution for all customers'

      def call(stats: false, **)
        boot_application!

        if stats
          show_password_stats
        else
          puts 'Usage: bin/ots passwords --stats'
          puts ''
          puts 'Options:'
          puts '  --stats    Show password hash algorithm distribution'
        end
      end

      private

      def show_password_stats
        bcrypt_count  = 0
        argon2_count  = 0
        no_pass_count = 0
        total_count   = 0

        puts 'Scanning customer password hashes...'
        puts ''

        Onetime::Customer.instances.all.each do |objid|
          cust = Onetime::Customer.load(objid)

          if cust.nil?
            # Stale reference in instances set
            next
          end

          total_count += 1

          unless cust.has_passphrase?
            no_pass_count += 1
            next
          end

          if cust.argon2_hash?(cust.passphrase)
            argon2_count += 1
          else
            bcrypt_count += 1
          end
        end

        with_password = bcrypt_count + argon2_count

        puts 'Password Hash Statistics'
        puts '=' * 40
        puts ''
        puts format('  BCrypt (legacy):  %6d (%5.1f%%)', bcrypt_count, percent(bcrypt_count, with_password))
        puts format('  Argon2id (new):   %6d (%5.1f%%)', argon2_count, percent(argon2_count, with_password))
        puts format('  No password:      %6d', no_pass_count)
        puts '  ' + '-' * 30
        puts format('  With password:    %6d', with_password)
        puts format('  Total customers:  %6d', total_count)
        puts ''

        if bcrypt_count.positive?
          puts 'Migration status: IN PROGRESS'
          puts "  #{bcrypt_count} customers will migrate on next login"
        else
          puts 'Migration status: COMPLETE'
          puts '  All passwords are using argon2id'
        end
      end

      def percent(count, total)
        return 0.0 if total.zero?

        (count.to_f / total * 100)
      end
    end

    register 'passwords', PasswordsCommand
  end
end
