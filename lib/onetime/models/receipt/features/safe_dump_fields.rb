# lib/onetime/models/receipt/features/safe_dump_fields.rb
#
# frozen_string_literal: true

# =============================================================================
# STATE TERMINOLOGY MIGRATION REFERENCE
# =============================================================================
# This section documents the field mappings for upgrading existing installations.
#
# LEGACY → NEW FIELD MAPPINGS:
#   State values:
#     'viewed'   → 'previewed'  (secret link accessed, confirmation shown)
#     'received' → 'revealed'   (secret content decrypted/consumed)
#
#   Timestamp fields:
#     viewed    → previewed  (when link was first accessed)
#     received  → revealed   (when secret was actually revealed)
#
#   Boolean fields:
#     is_viewed   → is_previewed  (has the link been accessed?)
#     is_received → is_revealed   (has the secret been revealed?)
#
# API BACKWARD COMPATIBILITY:
#   safe_dump returns BOTH old and new field names:
#     - `viewed` field: falls back to `previewed` if `viewed` is nil
#     - `received` field: falls back to `revealed` if `revealed` is nil
#     - `is_viewed`: true if state is 'previewed' OR legacy 'viewed'
#     - `is_received`: true if state is 'revealed' OR legacy 'received'
#
# MIGRATION SCRIPT REQUIREMENTS:
#   For each receipt in Redis:
#     1. If state='viewed', set state='previewed'
#     2. If state='received', set state='revealed'
#     3. Copy `viewed` → `previewed` (if `previewed` is nil)
#     4. Copy `received` → `revealed` (if `revealed` is nil)
#   Legacy fields can be retained for rollback safety.
# =============================================================================

module Onetime::Receipt::Features
  module SafeDumpFields
    # Register our custom SafeDump feature with a unique
    Onetime::Receipt.add_feature self, :safe_dump_fields

    def self.included(base)
      # Lambda to handle counter fields that may be nil/empty - returns '0'
      # if empty, otherwise the string value

      # Enable the Familia SafeDump feature
      base.feature :safe_dump

      # NOTE: The SafeDump mixin caches the safe_dump_field_map so updating this list
      # with hot reloading in dev mode will not work. You will need to restart the
      # server to see the changes.
      base.safe_dump_field :identifier, ->(obj) { obj.identifier }
      base.safe_dump_field :key, ->(obj) { obj.identifier }
      base.safe_dump_field :custid
      base.safe_dump_field :owner_id
      base.safe_dump_field :state
      base.safe_dump_field :secret_shortid,
        ->(m) {
                val = m.secret_shortid.to_s
                val.empty? ? m.secret_identifier.to_s.slice(0, 8) : val
        }
      base.safe_dump_field :secret_identifier
      base.safe_dump_field :secret_ttl, ->(m) { m.secret_ttl || -1 }
      base.safe_dump_field :metadata_ttl, ->(m) { m.lifespan }
      base.safe_dump_field :receipt_ttl, ->(m) { m.lifespan }
      base.safe_dump_field :lifespan
      base.safe_dump_field :share_domain
      base.safe_dump_field :created
      base.safe_dump_field :updated
      base.safe_dump_field :shared
      base.safe_dump_field :recipients
      base.safe_dump_field :memo
      base.safe_dump_field :shortid, ->(m) { m.identifier.slice(0, 8) }
      base.safe_dump_field :show_recipients, ->(m) { !m.recipients.to_s.empty? }

      # New canonical timestamp fields
      base.safe_dump_field :previewed
      base.safe_dump_field :revealed

      # New canonical boolean fields
      base.safe_dump_field :is_previewed, ->(m) { m.state?(:previewed) }

      # BACKWARD COMPAT: Returns previewed timestamp for legacy clients
      # Falls back to previewed if viewed is nil (new data)
      base.safe_dump_field :viewed, ->(m) { m.viewed.to_s.empty? ? m.previewed : m.viewed }
      # BACKWARD COMPAT: Returns revealed timestamp for legacy clients
      # Falls back to revealed if received is nil (new data)
      base.safe_dump_field :received, ->(m) { m.received.to_s.empty? ? m.revealed : m.received }
      base.safe_dump_field :burned

      # BACKWARD COMPAT: Returns true if previewed OR legacy viewed
      base.safe_dump_field :is_viewed, ->(m) { m.state?(:previewed) || m.state?(:viewed) }
      # BACKWARD COMPAT: Returns true if revealed OR legacy received
      base.safe_dump_field :is_received, ->(m) { m.state?(:revealed) || m.state?(:received) }
      base.safe_dump_field :is_revealed, ->(m) { m.state?(:revealed) || m.state?(:received) }
      base.safe_dump_field :is_burned, ->(m) { m.state?(:burned) }
      base.safe_dump_field :is_expired, ->(m) { m.state?(:expired) }
      base.safe_dump_field :is_orphaned, ->(m) { m.state?(:orphaned) }
      base.safe_dump_field :is_destroyed,
        ->(m) {
          m.state?(:revealed) || m.state?(:received) ||
            m.state?(:burned) || m.state?(:expired) || m.state?(:orphaned)
        }
      # We use the hash syntax here since `:truncated?` is not a valid symbol.
      # base.safe_dump_field :is_truncated, ->(m) { m.truncated? }
      base.safe_dump_field :has_passphrase, ->(m) { m.has_passphrase? }
      base.safe_dump_field :kind
    end
  end
end
