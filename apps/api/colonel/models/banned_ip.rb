# lib/onetime/models/banned_ip.rb
#
# frozen_string_literal: true

require 'ipaddr'

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

    # Create unique index on IP address/CIDR
    class_hashkey :ip_index

    def init
      self.banned_at                ||= Familia.now.to_i
      self.class.ip_index[ip_address] = objid if ip_address
    end

    class << self
      def ban!(ip_address, reason: nil, banned_by: nil, expiration: nil)
        # Check if already banned (exact match)
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

      # Check if an IP address is banned using CIDR matching
      #
      # @param ip_address_to_check [String] IP address to check
      # @return [Boolean] True if IP is banned
      def banned?(ip_address_to_check)
        return false if ip_address_to_check.to_s.empty?

        begin
          ip_to_check = IPAddr.new(ip_address_to_check)

          # Check all banned IPs/CIDRs for matches
          ip_index.keys.any? do |banned_cidr_string|
            begin
              banned_cidr = IPAddr.new(banned_cidr_string)
              banned_cidr.include?(ip_to_check)
            rescue IPAddr::InvalidAddressError
              # Skip invalid entries
              false
            end
          end
        rescue IPAddr::InvalidAddressError
          # Invalid IP to check - not banned
          false
        end
      end

      def count
        instances.count # e.g. zcard dbkey
      end

    end
  end
end
