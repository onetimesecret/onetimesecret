# lib/onetime/cli/ratelimit_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    # Emits valkey-cli commands for inspecting or clearing the in-Redis state
    # used by the security rate limiters in lib/onetime/security/*_rate_limiter.rb.
    #
    # The CLI does not touch Redis itself. Output is meant to be piped into
    # valkey-cli, or pasted into a ticket / shell session for review first:
    #
    #   bin/ots ratelimit keys feedback 1.2.3.4
    #   bin/ots ratelimit keys feedback 1.2.3.4 | grep -v '^#' | valkey-cli
    #
    # Adding a new limiter: add one row to LIMITERS with the key templates
    # used by the module's private *_key methods.
    class RatelimitCommand < DelayBootCommand
      LIMITERS = {
        'feedback' => {
          subject: 'IP address',
          keys: ['feedback:submissions:%s', 'feedback:locked:%s'],
        },
        'passphrase' => {
          subject: 'secret identifier',
          keys: ['passphrase:attempts:%s', 'passphrase:locked:%s'],
        },
        'invite' => {
          subject: 'IP address',
          keys: ['invite_attempts:%s', 'invite_locked:%s'],
        },
        'dns' => {
          subject: 'domain identifier (sanitized)',
          keys: ['dns:ratelimit:%s'],
        },
      }.freeze

      desc 'List known rate limiters and their subject types'

      def call(**)
        puts 'Known rate limiters:'
        width = LIMITERS.keys.map(&:length).max
        LIMITERS.each do |kind, meta|
          puts "  #{kind.ljust(width)}  subject: #{meta[:subject]}"
        end
        puts
        puts 'Usage:'
        puts '  bin/ots ratelimit keys <kind> <subject>'
      end
    end

    class RatelimitKeysCommand < DelayBootCommand
      desc 'Emit valkey-cli commands to inspect and clear a rate-limit entry'

      argument :kind,
        type: :string,
        required: true,
        desc: "Rate limiter kind (#{RatelimitCommand::LIMITERS.keys.join(', ')})"
      argument :subject,
        type: :string,
        required: true,
        desc: 'IP, identifier, or other lookup key the limiter uses'

      def call(kind:, subject:, **)
        meta = RatelimitCommand::LIMITERS[kind]
        unless meta
          warn "Unknown rate limiter: #{kind.inspect}"
          warn "Known: #{RatelimitCommand::LIMITERS.keys.join(', ')}"
          exit 1
        end

        keys = meta[:keys].map { |tmpl| format(tmpl, subject) }

        puts '# inspect'
        keys.each do |k|
          puts "TTL #{k}"
          puts "GET #{k}"
        end
        puts '# clear'
        puts "DEL #{keys.join(' ')}"
      end
    end

    register 'ratelimit',      RatelimitCommand
    register 'ratelimit keys', RatelimitKeysCommand
  end
end
