# lib/onetime/cli/passwords_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # CLI command for password hash statistics.
    #
    # Usage:
    #   bin/ots passwords --stats    # Show password hash statistics
    #
    class PasswordsCommand < Command
      desc 'Password hash statistics'

      option :stats,
        type: :boolean,
        default: false,
        desc: 'Show password hash statistics for all customers'

      def call(stats: false, **)
        boot_application!

        if stats
          show_password_stats
        else
          puts 'Usage: bin/ots passwords --stats'
          puts ''
          puts 'Options:'
          puts '  --stats    Show password hash statistics'
        end
      end

      private

      def show_password_stats
        argon2_count  = 0
        no_pass_count = 0
        total_count   = 0

        puts 'Scanning customer password hashes...'
        puts ''

        Onetime::Customer.instances.all.each do |objid|
          cust = Onetime::Customer.load(objid)

          if cust.nil?
            next
          end

          total_count += 1

          unless cust.has_passphrase?
            no_pass_count += 1
            next
          end

          argon2_count += 1
        end

        puts 'Password Hash Statistics'
        puts '=' * 40
        puts ''
        puts format('  Argon2id:         %6d', argon2_count)
        puts format('  No password:      %6d', no_pass_count)
        puts '  ' + ('-' * 30)
        puts format('  Total customers:  %6d', total_count)
      end
    end

    register 'passwords', PasswordsCommand
  end
end
