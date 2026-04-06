# lib/onetime/models/customer/features/colonel_assignment.rb
#
# frozen_string_literal: true

# Colonel List Utilities
#
# Provides methods to check if an email is in the configured colonels list.
# Does NOT auto-assign roles - colonel promotion is managed exclusively
# via CLI commands (bin/ots role promote).
#
# The colonels list is configured via:
# - ENV['COLONEL'] environment variable
# - Parsed into site.authentication.colonels in config
#
# Security considerations:
# - Email normalized with Unicode case folding for international addresses
#
module Onetime
  class Customer
    module Features
      module ColonelAssignment
        extend self

        # Check if an email address is in the colonels list
        #
        # @param email [String] The email to check
        # @return [Boolean] true if email matches a configured colonel
        def colonel?(email)
          return false if email.nil? || email.empty?

          normalized = email.to_s.strip.unicode_normalize(:nfc).downcase(:fold)
          colonels_list.include?(normalized)
        end

        # Get the normalized colonels list from config
        #
        # Handles both YAML array entries and comma-separated values within entries.
        # This supports the common pattern: COLONEL=admin@example.com,backup@example.com
        #
        # @return [Array<String>] Normalized email addresses
        def colonels_list
          raw_list = OT.conf.dig('site', 'authentication', 'colonels') || []

          raw_list
            .flat_map { |entry| entry.to_s.split(',') }
            .map { |col| col.to_s.strip.unicode_normalize(:nfc).downcase(:fold) }
            .compact
            .reject(&:empty?)
        end
      end
    end
  end
end
