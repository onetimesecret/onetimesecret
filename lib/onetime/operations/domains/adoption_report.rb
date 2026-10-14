# lib/onetime/operations/domains/adoption_report.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/config_registry'

module Onetime
  module Operations
    module Domains
      # What an adopted orphan is left with, for the operator who adopted it.
      #
      # Adoption (CustomDomain.claim_orphaned_domain) keeps the record's
      # identifier. It resets the ownership verification and issues a new TXT
      # value; everything else keyed by the identifier stays: the per-domain
      # configs, the brand, logo and icon hashes, and the receipts index. The
      # operator tools (Create, Repair, Transfer) show this report so the
      # operator can decide what to do with that state. Nothing is cleared
      # here.
      #
      # Built after the adoption has landed, so it never raises: a read that
      # fails is logged and the kept-state fields are nil.
      #
      # @!attribute extid [r] String — the adopted domain's extid
      # @!attribute txt_record [r] String, nil — the TXT record name the new
      #   owner publishes (A-label form)
      # @!attribute txt_value [r] String, nil — the new TXT value
      # @!attribute configs [r] Array<String>, nil — ConfigRegistry kind slugs
      #   that have a record for the domain
      # @!attribute brand_keys [r] Integer, nil — fields in the brand hash
      # @!attribute logo [r] Boolean, nil — a logo is stored
      # @!attribute icon [r] Boolean, nil — an icon is stored
      # @!attribute receipts [r] Integer, nil — entries in the domain's
      #   receipts index
      AdoptionReport = Data.define(
        :extid,
        :txt_record,
        :txt_value,
        :configs,
        :brand_keys,
        :logo,
        :icon,
        :receipts,
      ) do
        # @param domain [Onetime::CustomDomain] the adopted record
        # @return [AdoptionReport]
        def self.for(domain)
          new(
            extid: domain.extid,
            txt_record: txt_record_for(domain),
            txt_value: domain.txt_validation_value,
            **kept_state(domain),
          )
        end

        # @return [Hash{Symbol => Object}] the kept-state attributes, all nil
        #   when they could not be read
        def self.kept_state(domain)
          registry = Onetime::CustomDomain::ConfigRegistry
          {
            configs: registry.slugs.select { |slug| registry.model_for(slug).exists_for_domain?(domain.identifier) },
            brand_keys: domain.brand.size,
            logo: !domain.logo.empty?,
            icon: !domain.icon.empty?,
            receipts: domain.receipts.size,
          }
        rescue StandardError => ex
          OT.le "[Domains::AdoptionReport] Could not read the kept state of #{domain.extid}: #{ex.class}: #{ex.message}"
          { configs: nil, brand_keys: nil, logo: nil, icon: nil, receipts: nil }
        end

        def self.txt_record_for(domain)
          domain.validation_record
        rescue Onetime::DomainValidation::AsciiHostname::ConversionError
          nil
        end
        private_class_method :kept_state, :txt_record_for

        # @return [Boolean] whether the kept state could be read
        def kept_state_read?
          !configs.nil?
        end

        # One phrase for what the domain kept, e.g.
        # "configs: signin, sso; brand (3 fields); logo; 12 receipts".
        #
        # @return [String]
        def kept_summary
          return 'could not be read' unless kept_state_read?

          parts = []
          parts << "configs: #{configs.join(', ')}" unless configs.empty?
          parts << "brand (#{brand_keys} fields)" if brand_keys.positive?
          parts << 'logo' if logo
          parts << 'icon' if icon
          parts << "#{receipts} receipts" if receipts.positive?
          parts.empty? ? 'nothing' : parts.join('; ')
        end

        # Lines for operator output (CLI text, Repair's repairs_applied).
        #
        # @return [Array<String>]
        def lines
          [
            "Ownership verification reset; new TXT value #{txt_record} = #{txt_value}",
            "Kept from the earlier owner: #{kept_summary}",
          ]
        end

        # @return [Hash] JSON-ready form for --json and colonel responses
        def to_payload
          {
            verification_reset: true,
            txt_validation_record: txt_record,
            txt_validation_value: txt_value,
            kept: {
              configs: configs,
              brand_keys: brand_keys,
              logo: logo,
              icon: icon,
              receipts: receipts,
            },
          }
        end

        # Writes the report to the application log.
        #
        # @param source [String] log tag of the operator tool
        # @return [void]
        def log(source)
          OT.info "[#{source}] Adopted orphaned domain #{extid}: ownership verification reset, " \
                  "new TXT value issued; kept: #{kept_summary}"
        end
      end
    end
  end
end
