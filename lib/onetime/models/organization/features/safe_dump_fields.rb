# lib/onetime/models/organization/features/safe_dump_fields.rb
#
# frozen_string_literal: true

module Onetime::Organization::Features
  module SafeDumpFields
    # Register our custom SafeDump feature with a unique identifier
    Onetime::Organization.add_feature self, :safe_dump_fields

    def self.included(base)
      # Enable the Familia SafeDump feature
      base.feature :safe_dump

      # NOTE: The SafeDump mixin caches the safe_dump_field_map so updating this list
      # with hot reloading in dev mode will not work. You will need to restart the
      # server to see the changes.
      base.safe_dump_field :identifier, ->(obj) { obj.identifier }
      base.safe_dump_field :objid
      base.safe_dump_field :extid
      base.safe_dump_field :display_name
      base.safe_dump_field :description
      base.safe_dump_field :owner_id
      # Immutable audit field (ADR-012). owner_id is kept for backward-
      # compatible JSON consumers during the deprecation window; the two
      # are kept identical via Organization.create! wiring and the
      # standardize_owner_id housekeeping chore.
      base.safe_dump_field :created_by
      base.safe_dump_field :contact_email
      base.safe_dump_field :billing_email
      base.safe_dump_field :is_default
      base.safe_dump_field :archived_at
      base.safe_dump_field :planid
      base.safe_dump_field :member_count, ->(org) { org.member_count }
      base.safe_dump_field :domain_count, ->(org) { org.domain_count }
      base.safe_dump_field :updated
      base.safe_dump_field :created

      # Entitlements and limits from plan (via WithEntitlements feature)
      # These enable frontend feature gating and quota display
      base.safe_dump_field :entitlements, ->(org) { org.entitlements }
      base.safe_dump_field :limits,
        ->(org) {
                # Convert Float::INFINITY to -1 for JSON serialization (unlimited)
                normalize = ->(val) { val == Float::INFINITY ? -1 : val.to_i }
                {
                  teams: normalize.call(org.limit_for(:teams)),
                  total_members_per_org: normalize.call(org.limit_for(:total_members_per_org)),
                  custom_domains: normalize.call(org.limit_for(:custom_domains)),
                }
        }
    end
  end
end
