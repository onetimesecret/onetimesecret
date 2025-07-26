# apps/api/v2/models/custom_domain.rb

require 'public_suffix'

# Tryouts:
# - tests/unit/ruby/try/20_models/27_domains_try.rb
# - tests/unit/ruby/try/20_models/27_domains_publicsuffix_try.rb

# Custom Domain
#
# Every customer can have one or more custom domains.
#
# The list of custom domains that are associated to a customer is
# distinct from a customer's subdomain.
#
# General techical terminology:
#
# `tld`` = Top level domain, this is in reference to the last segment of a
# domain, sometimes the part that is directly after the "dot" symbol. For
# example, mozilla.org, the .org portion is the tld.
#
# `sld` = Second level domain, a domain that is directly below a top-level
# domain. For example, in https://www.mozilla.org/en-US/, mozilla is the
# second-level domain of the .org tld.
#
# `trd` = Transit routing domain, or known as a subdomain. This is the part of
# the domain that is before the sld or root domain. For example, in
# https://www.mozilla.org/en-US/, www is the trd.
#
# `FQDN` = Fully Qualified Domain Names, are domain names that are written with
# the hostname and the domain name, and include the top-level domain, the
# format looks like [hostname].[domain].[tld]. for ex. [www].[mozilla].[org].
#
module V2
  class CustomDomain < Familia::Horreum

    # Parses the vhost JSON string into a Ruby hash
    #
    # @return [Hash] The parsed vhost configuration, or empty hash if parsing fails
    # @note Returns empty hash in two cases:
    #   1. When vhost is nil or empty string
    #   2. When JSON parsing fails (invalid JSON)
    # @example
    #   custom_domain.vhost = '{"ssl": true, "redirect": "https"}'
    #   custom_domain.parse_vhost #=> {"ssl"=>true, "redirect"=>"https"}
    def parse_vhost
      return {} if vhost.to_s.empty?

      JSON.parse(vhost)
    rescue JSON::ParserError => ex
      OT.le "[CustomDomain.parse_vhost] Error parsing JSON: #{vhost.inspect} - #{ex}"
      {}
    end

    def to_s
      # If we can treat familia objects as strings, then passing them as method
      # arguments we don't need to check whether it is_a? RedisObject or not;
      # we can simply call `fobj.to_s`. In both cases the result is the unqiue
      # ID of the familia object. Usually that is all we need to maintain the
      # relation records -- we don't actually need the instance of the familia
      # object itself.
      #
      # As a pilot to trial this out, Customer has the equivalent method and
      # comment. See the ClassMethods below for usage details.
      identifier.to_s
    end

    def check_identifier!
      if identifier.to_s.empty?
        raise "Identifier cannot be empty for #{self.class}"
      end
    end

    # Destroy the custom domain record
    #
    # Removes the domain identifier from the CustomDomain values
    # and then calls the superclass destroy method
    #
    # @param args [Array] Additional arguments to pass to the superclass destroy method
    # @return [Object] The result of the superclass destroy method
    def delete!(*args)
      V2::CustomDomain.rem self
      super # we may prefer to call self.clear here instead
    end

    # Removes all Redis keys associated with this custom domain.
    #
    # This includes:
    # - The main Redis key for the custom domain (`self.dbkey`)
    # - Redis keys of all related objects specified in `self.class.data_types`
    #
    # @param customer [V2::Customer, nil] The customer to remove the domain from
    # @return [void]
    def destroy!(customer = nil)
      keys_to_delete = [dbkey]

      # This produces a list of dbkeys for each of the DataType
      # relations defined for this model.
      # See Familia::Features::Expiration for references implementation.
      if self.class.has_relations?
        related_names = self.class.data_types.keys
        OT.ld "[destroy!] #{self.class} has relations: #{related_names}"

        related_keys = related_names.filter_map do |name|
          relation = send(name) # e.g. self.brand
          relation.dbkey
        end

        # Append related Redis keys to the deletion list.
        keys_to_delete.concat(related_keys)
      end

      dbclient.multi do |multi|
        multi.del(dbkey)
        # Also remove from the class-level values, :display_domains, :owners
        multi.zrem(V2::CustomDomain.values.dbkey, identifier)
        multi.hdel(V2::CustomDomain.display_domains.dbkey, display_domain)
        multi.hdel(V2::CustomDomain.owners.dbkey, display_domain)
        multi.del(brand.dbkey)
        multi.del(logo.dbkey)
        multi.del(icon.dbkey)
        unless customer.nil?
          multi.zrem(customer.custom_domains.dbkey, display_domain)
        end
      end
    rescue Redis::BaseError => ex
      OT.le "[CustomDomain.destroy!] Redis error: #{ex.message}"
      raise Onetime::Problem, 'Unable to delete custom domain'
    end

    # Checks if the domain is an apex domain.
    # An apex domain is a domain without any subdomains.
    #
    # Note: A subdomain can include nested subdomains (e.g., b.a.example.com),
    # whereas TRD (Transit Routing Domain) refers to the part directly before
    # the SLD.
    #
    # @return [Boolean] true if the domain is an apex domain, false otherwise
    def apex?
      subdomain.empty?
    end

    # Overrides Familia::Horreum#exists? to handle connection pool issues
    #
    # The original implementation may return false for existing keys
    # when the connection is returned to the pool before checking.
    # This implementation uses a fresh connection for the check.
    #
    # @return [Boolean] true if the domain exists in Redis
    def exists?
      dbclient.exists?(dbkey)
    end

    def allow_public_homepage?
      brand.get('allow_public_homepage').to_s == 'true'
    end

    def allow_public_api?
      brand.get('allow_public_api').to_s == 'true'
    end

    # Validates the format of TXT record host and value used for domain verification.
    # The host must be alphanumeric with dots, underscores, or hyphens only.
    # The value must be a 32-character hexadecimal string.
    #
    # @raise [Onetime::Problem] If the TXT record host or value format is invalid
    # @return [void]
    def validate_txt_record!
      unless txt_validation_host.to_s.match?(/\A[a-zA-Z0-9._-]+\z/)
        raise Onetime::Problem, 'TXT record hostname can only contain letters, numbers, dots, underscores, and hyphens'
      end

      unless txt_validation_value.to_s.match?(/\A[a-f0-9]{32}\z/)
        raise Onetime::Problem, 'TXT record value must be a 32-character hexadecimal string'
      end
    end

    # Generates a TXT record for domain ownership verification.
    # Format: _onetime-challenge-<short_id>[.subdomain]
    #
    # The record consists of:
    # - A prefix (_onetime-challenge-)
    # - First 7 chars of the domain identifier
    # - Subdomain parts if present (e.g. .www or .status.www)
    # - A 32-char random hex value
    #
    # @return [Array<String, String>] The TXT record host and value
    # @raise [Onetime::Problem] If the generated record is invalid
    #
    # Examples:
    #   _onetime-challenge-domainid -> 7709715a6411631ce1d447428d8a70
    #   _onetime-challenge-domainid.status -> cd94fec5a98fd33a0d70d069acaae9
    #
    def generate_txt_validation_record
      # Include a short identifier that is unique to this domain. This
      # allows for multiple customers to use the same domain without
      # conflicting with each other.
      shortid     = identifier.to_s[0..6]
      record_host = "#{self.class.txt_validation_prefix}-#{shortid}"

      # Append the TRD if it exists. This allows for multiple subdomains
      # to be used for the same domain.
      # e.g. The `status` in status.example.com.
      unless trd.to_s.empty?
        record_host = "#{record_host}.#{trd}"
      end

      # The value needs to be sufficiently unique and non-guessable to
      # function as a challenge response. IOW, if we check the DNS for
      # the domain and match the value we've generated here, then we
      # can reasonably assume that the customer controls the domain.
      record_value = SecureRandom.hex(16)

      OT.info "[CustomDomain] Generated txt record #{record_host} -> #{record_value}"

      @txt_validation_host  = record_host
      @txt_validation_value = record_value

      validate_txt_record!

      # These can now be displayed to the customer for them
      # to continue the validation process.
      [record_host, record_value]
    end

    # The fully qualified domain name for the TXT record.
    #
    # Used to validate the domain ownership by the customer
    # via the Approximated check_records API.
    #
    # e.g. `_onetime-challenge-domainid.froogle.com`
    #
    def validation_record
      [txt_validation_host, base_domain].join('.')
    end

    # Returns the current verification state of the custom domain
    #
    # States:
    # - :unverified  Initial state, no verification attempted
    # - :pending     TXT record generated but DNS not resolving
    # - :resolving    TXT record and CNAME are resolving but not yet matching
    # - :verified    TXT and CNAME are resolving and TXT record matches
    #
    # @return [Symbol] The current verification state
    def verification_state
      return :unverified unless txt_validation_value

      if resolving.to_s == 'true'
        verified.to_s == 'true' ? :verified : :resolving
      else
        :pending
      end
    end

    # Checks if this domain is ready to serve traffic
    #
    # A domain is considered ready when:
    # 1. The ownership is verified via TXT record
    # 2. The domain is resolving to our servers
    #
    # @return [Boolean] true if domain is verified and resolving
    def ready?
      verification_state == :verified
    end

  end
end

require_relative 'custom_domain/definition'
require_relative 'custom_domain/class_methods'
