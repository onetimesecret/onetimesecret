# lib/onetime/domain_validation/sender_strategies/base_strategy.rb
#
# frozen_string_literal: true

require 'resolv'

module Onetime
  module DomainValidation
    module SenderStrategies
      # BaseStrategy - Interface for sender domain validation strategies.
      #
      # Each provider strategy (SES, SendGrid, Lettermint) implements these
      # methods to generate the DNS records a customer must configure and to
      # verify those records via live DNS lookups.
      #
      # The mailer_config argument carries provider credentials and a domain_id
      # foreign key. The associated CustomDomain's display_domain is the domain
      # name used in record generation and verification.
      #
      class BaseStrategy
        # Returns the DNS records the customer must configure for this provider.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>] Each hash contains:
        #   - :type [String] Record type (TXT, CNAME, MX)
        #   - :host [String] DNS hostname to create
        #   - :value [String] Expected record value
        #   - :purpose [String] Human-readable description (e.g. "DKIM", "SPF")
        #
        def required_dns_records(mailer_config)
          raise NotImplementedError, "#{self.class} must implement #required_dns_records"
        end

        # Queries live DNS and compares against expected records.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>] Each hash contains:
        #   - :type [String] Record type (TXT, CNAME, MX)
        #   - :host [String] DNS hostname queried
        #   - :expected [String] Expected value
        #   - :actual [Array<String>] Values found in DNS
        #   - :verified [Boolean] Whether a match was found
        #   - :purpose [String] Human-readable description
        #
        def verify_dns_records(mailer_config)
          raise NotImplementedError, "#{self.class} must implement #verify_dns_records"
        end

        # Returns the strategy name for logging and debugging.
        #
        # @return [String] Strategy identifier (e.g. "ses", "sendgrid")
        #
        def strategy_name
          self.class.name.split('::').last.sub('Validation', '').downcase
        end

        private

        # Resolve the display_domain from a mailer_config's associated CustomDomain.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [String] The domain name (e.g. "secrets.example.com")
        # @raise [ArgumentError] If the domain cannot be resolved
        #
        def resolve_domain(mailer_config)
          custom_domain = mailer_config.custom_domain
          unless custom_domain
            raise ArgumentError,
              "MailerConfig #{mailer_config.domain_id} has no associated CustomDomain"
          end

          domain = custom_domain.display_domain.to_s
          if domain.empty?
            raise ArgumentError,
              "CustomDomain #{custom_domain.identifier} has no display_domain"
          end

          domain
        end

        # Query TXT records for a hostname.
        #
        # @param hostname [String] Fully qualified hostname
        # @param resolver [Resolv::DNS] Optional resolver instance
        # @return [Array<String>] TXT record values found
        #
        def lookup_txt_records(hostname, resolver: nil)
          dns       = resolver || Resolv::DNS.new
          resources = dns.getresources(hostname, Resolv::DNS::Resource::IN::TXT)
          resources.map { |r| r.strings.join }
        rescue Resolv::ResolvError, Resolv::ResolvTimeout => ex
          OT.ld "[SenderStrategies] TXT lookup failed for #{hostname}: #{ex.message}"
          []
        ensure
          dns.close if dns && resolver.nil?
        end

        # Query CNAME records for a hostname.
        #
        # @param hostname [String] Fully qualified hostname
        # @param resolver [Resolv::DNS] Optional resolver instance
        # @return [Array<String>] CNAME target values found
        #
        def lookup_cname_records(hostname, resolver: nil)
          dns       = resolver || Resolv::DNS.new
          resources = dns.getresources(hostname, Resolv::DNS::Resource::IN::CNAME)
          resources.map { |r| r.name.to_s }
        rescue Resolv::ResolvError, Resolv::ResolvTimeout => ex
          OT.ld "[SenderStrategies] CNAME lookup failed for #{hostname}: #{ex.message}"
          []
        ensure
          dns.close if dns && resolver.nil?
        end

        # Query MX records for a hostname.
        #
        # @param hostname [String] Fully qualified hostname
        # @param resolver [Resolv::DNS] Optional resolver instance
        # @return [Array<String>] MX exchange hostnames found
        #
        def lookup_mx_records(hostname, resolver: nil)
          dns       = resolver || Resolv::DNS.new
          resources = dns.getresources(hostname, Resolv::DNS::Resource::IN::MX)
          resources.map { |r| r.exchange.to_s }
        rescue Resolv::ResolvError, Resolv::ResolvTimeout => ex
          OT.ld "[SenderStrategies] MX lookup failed for #{hostname}: #{ex.message}"
          []
        ensure
          dns.close if dns && resolver.nil?
        end

        # Verify a single DNS record by comparing expected value against live DNS.
        #
        # Uses a shared resolver to avoid opening/closing connections per record.
        #
        # @param record [Hash] A record hash from required_dns_records
        # @param resolver [Resolv::DNS] Shared resolver instance
        # @return [Hash] Verification result
        #
        def verify_record(record, resolver:)
          actual = case record[:type]
                   when 'TXT'
                     lookup_txt_records(record[:host], resolver: resolver)
                   when 'CNAME'
                     lookup_cname_records(record[:host], resolver: resolver)
                   when 'MX'
                     lookup_mx_records(record[:host], resolver: resolver)
                   else
                     []
                   end

          verified = record_matches?(record[:type], record[:value], actual)

          {
            type: record[:type],
            host: record[:host],
            expected: record[:value],
            actual: actual,
            verified: verified,
            purpose: record[:purpose],
          }
        end

        # Check whether the expected value appears in the actual DNS results.
        #
        # For TXT/SPF records: customers commonly merge multiple provider
        # includes into one SPF record (e.g., "v=spf1 include:amazonses.com
        # include:sendgrid.net ~all"). We extract the include: directive from
        # the expected value and check that it appears in any actual TXT record
        # that starts with "v=spf1". For non-SPF TXT records, full substring
        # match is used.
        #
        # For CNAME and MX records: exact match after downcasing and stripping
        # trailing dots.
        #
        # @param type [String] Record type
        # @param expected [String] Expected value
        # @param actual_values [Array<String>] DNS results
        # @return [Boolean]
        #
        def record_matches?(type, expected, actual_values)
          normalized_expected = expected.to_s.downcase.chomp('.')

          case type
          when 'TXT'
            if normalized_expected.start_with?('v=spf1')
              # Extract the include: directive and verify it appears in an
              # actual SPF record, regardless of other mechanisms present
              spf_include = normalized_expected[/include:\S+/]
              if spf_include
                actual_values.any? do |v|
                  downcased = v.downcase
                  downcased.start_with?('v=spf1') && downcased.include?(spf_include)
                end
              else
                actual_values.any? { |v| v.downcase.include?(normalized_expected) }
              end
            else
              actual_values.any? { |v| v.downcase.include?(normalized_expected) }
            end
          when 'CNAME', 'MX'
            actual_values.any? { |v| v.downcase.chomp('.') == normalized_expected }
          else
            false
          end
        end

        # Run verification for all required records using a single resolver.
        #
        # Concrete strategies can call this from verify_dns_records to avoid
        # duplicating the resolver lifecycle.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>] Verification results
        #
        def verify_all_records(mailer_config)
          records  = required_dns_records(mailer_config)
          resolver = Resolv::DNS.new

          records.map { |record| verify_record(record, resolver: resolver) }
        ensure
          resolver&.close
        end
      end
    end
  end
end
