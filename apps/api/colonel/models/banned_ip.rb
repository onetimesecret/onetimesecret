# lib/onetime/models/banned_ip.rb
#
# frozen_string_literal: true

module Onetime
  class BannedIP < Familia::Horreum
    include Familia::Features::Autoloader

    using Familia::Refinements::TimeLiterals

    prefix :banned_ip

    feature :object_identifier
    feature :expiration

    identifier_field :objid

    field :ip_address
    field :reason
    field :banned_by
    field :banned_at

    # Create unique index on IP address
    class_hashkey :ip_index

    def init
      self.banned_at                ||= Familia.now.to_i
      self.class.ip_index[ip_address] = objid if ip_address
    end

    class << self
      def ban!(ip_address, reason: nil, banned_by: nil, expiration: nil)
        # Check if already banned
        existing_id = ip_index[ip_address]
        return load(existing_id) if existing_id

        # Create new ban
        banned_ip = new(
          ip_address: ip_address,
          reason: reason,
          banned_by: banned_by,
          banned_at: Familia.now.to_i,
        )

        banned_ip.default_expiration = expiration if expiration
        banned_ip.save

        # Add to index
        ip_index[ip_address] = banned_ip.objid

        banned_ip
      end

      def unban!(ip_address)
        existing_id = ip_index[ip_address]
        return false unless existing_id

        banned_ip = load(existing_id)
        return false unless banned_ip

        # Remove from index first
        ip_index.remove_field(ip_address)

        # Then destroy the record
        banned_ip.destroy!
        true
      end

      def banned?(ip_address)
        ip_index.key?(ip_address)
      end

      def count
        instances.count # e.g. zcard dbkey
      end

    end
  end
end
