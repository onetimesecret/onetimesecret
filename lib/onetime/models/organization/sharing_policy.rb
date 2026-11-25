# lib/onetime/models/organization/sharing_policy.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/ascii_hostname'

module Onetime
  class Organization
    module SharingPolicy
      DEFAULT     = {
        'recipient_email_mode' => 'unrestricted',
        'recipient_email_domains' => [].freeze,
        'passphrase_required' => false,
        'max_ttl' => nil,
      }.freeze
      EMAIL_MODES = %w[unrestricted disabled restricted].freeze
      DNS_LABEL   = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/
      # The public JSON contract uses JavaScript integer seconds.
      TTL_RANGE   = (60..((2**53) - 1))

      class Invalid < ArgumentError
        attr_reader :field

        def initialize(field)
          @field = field
          super("Invalid sharing policy field: #{field}")
        end
      end

      # A single Redis string keeps replacement independent of other org saves.
      def self.included(base)
        base.string :sharing_policy_json
      end

      def sharing_policy
        raw = sharing_policy_json.value
        return SharingPolicy::DEFAULT if raw.nil?

        SharingPolicy.normalize(JSON.parse(raw))
      end

      def replace_sharing_policy!(policy)
        self.sharing_policy_json = JSON.generate(SharingPolicy.normalize(policy))
      end

      def self.normalize(policy)
        unless policy.is_a?(Hash) && policy.size == DEFAULT.size && DEFAULT.keys.all? { |field| policy.key?(field) }
          raise Invalid, 'sharing_policy'
        end

        mode = policy['recipient_email_mode']
        raise Invalid, 'recipient_email_mode' unless EMAIL_MODES.include?(mode)
        raise Invalid, 'passphrase_required' unless [true, false].include?(policy['passphrase_required'])

        ttl = policy['max_ttl']
        raise Invalid, 'max_ttl' unless ttl.nil? || (ttl.is_a?(Integer) && TTL_RANGE.cover?(ttl))

        domains = policy['recipient_email_domains']
        raise Invalid, 'recipient_email_domains' unless domains.is_a?(Array)

        keys = domains.map { |domain| normalize_domain(domain) }.uniq
        raise Invalid, 'recipient_email_domains' if mode == 'restricted' && keys.empty?

        policy.merge('recipient_email_domains' => keys)
      end

      def self.normalize_domain(domain)
        key = Onetime::DomainValidation::AsciiHostname.comparison_key(domain.strip) if domain.is_a?(String)
        if key && key.bytesize <= 253 && key.include?('.') && key.split('.', -1).all? { |label| DNS_LABEL.match?(label) }
          return key
        end

        raise Invalid, 'recipient_email_domains'
      end
      private_class_method :normalize_domain
    end
  end
end
