# lib/onetime/cli/ratelimit_command.rb
#
# frozen_string_literal: true

require 'onetime/operations/ratelimit/registry'

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
      # SINGLE source of truth for the limiter kinds + key templates, now owned by
      # the extracted {Onetime::Operations::RateLimit::Registry} (ticket #44) and
      # shared with the colonel inspect/reset endpoints. Aliased here so every
      # existing `LIMITERS[...]` / `LIMITERS.keys` reference — and the emitted
      # valkey-cli output — stays byte-identical. The registry adds a lazy
      # `:dbclient` proc the CLI simply ignores (it never touches Redis itself).
      LIMITERS = Onetime::Operations::RateLimit::Registry::LIMITERS

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
        # Key derivation is now written once in the shared registry — the SAME
        # templates the colonel inspect/reset endpoints expand (ticket #44).
        keys = Onetime::Operations::RateLimit::Registry.keys_for(kind, subject)
        unless keys
          warn "Unknown rate limiter: #{kind.inspect}"
          warn "Known: #{RatelimitCommand::LIMITERS.keys.join(', ')}"
          exit 1
        end

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
