# lib/onetime/models/banned_ip.rb
#
# frozen_string_literal: true

module Onetime
  class BannedIP < Familia::Horreum
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
    unique_index :ip_address, :ip_index

    def init
      self.banned_at ||= Familia.now.to_i
    end

    class << self
      def ban!(ip_address, reason: nil, banned_by: nil, expiration: nil)
        # Check if already banned
        existing = find_by_ip_address(ip_address)
        return existing if existing

        # Create new ban
        banned_ip = new(
          ip_address: ip_address,
          reason: reason,
          banned_by: banned_by,
          banned_at: Familia.now.to_i
        )

        banned_ip.default_expiration = expiration if expiration
        banned_ip.save
        banned_ip
      end

      def unban!(ip_address)
        banned_ip = find_by_ip_address(ip_address)
        return false unless banned_ip

        banned_ip.destroy!
        true
      end

      def banned?(ip_address)
        ip_index.key?(ip_address)
      end
    end
  end
end
