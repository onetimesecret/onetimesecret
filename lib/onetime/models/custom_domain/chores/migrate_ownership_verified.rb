# lib/onetime/models/custom_domain/chores/migrate_ownership_verified.rb
#
# frozen_string_literal: true

# Copy the legacy ownership flag only when the canonical field is absent.
# Preserve the original bytes: both fields use the same native boolean reader,
# including its tolerance for legacy JSON-quoted strings and numeric values.
#
# Run after retiring legacy writers:
#   bin/ots housekeeping run Onetime::CustomDomain migrate_ownership_verified

module Onetime
  module Chores
    class MigrateOwnershipVerified
      # Reading and copying in one script prevents overwriting a concurrent
      # canonical write or recreating a domain deleted during the sweep.
      COPY_LUA = <<~LUA
        local legacy = redis.call('HGET', KEYS[1], 'verified')
        if legacy == false then
          return 0
        end
        return redis.call('HSETNX', KEYS[1], 'ownership_verified', legacy)
      LUA

      def call(domain)
        copied = domain.dbclient.eval(COPY_LUA, keys: [domain.dbkey]).to_i == 1
        return false unless copied

        Onetime.get_logger('Chores').info 'Copied legacy ownership verification',
          chore: :migrate_ownership_verified,
          domain_extid: domain.extid
        true
      end
    end
  end
end

Onetime::CustomDomain.chore :migrate_ownership_verified, Onetime::Chores::MigrateOwnershipVerified.new
