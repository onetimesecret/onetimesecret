
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

require 'public_suffix'

class Onetime::CustomDomain < Familia::Horreum
  include Gibbler::Complex

  db 6
  prefix :custom_domain

  feature :safe_dump

  identifier :derive_id

  # NOTE: The redis key used by older models for values is simply
  # "onetime:customdomain". We'll want to rename those at some point.
  class_sorted_set :values
  class_hashkey :owners

  field :display_domain
  field :custid
  field :domainid
  field :base_domain
  field :subdomain
  field :trd
  field :tld
  field :sld
  field :txt_validation_host
  field :txt_validation_value
  field :status
  field :vhost
  field :verified
  field :created
  field :updated
  field :_original_value

  @txt_validation_prefix = '_onetime-challenge'

  @safe_dump_fields = [
    :domainid,
    :display_domain,
    :custid,
    :base_domain,
    :subdomain,
    :trd,
    :tld,
    :sld,
    :_original_value,
    :txt_validation_host,
    :txt_validation_value,
    :status,
    { :vhost => ->(obj) { obj.parse_vhost } },
    :verified,
    :created,
    :updated
  ]

  # We need a minimum of a domain and customer id to create a custom
  # domain -- or more specifically, a custom domain indentifier. We
  # allow instantiating a custom domain without a customer id, but
  # instead raise a fuss if we try to save it later without one.
  #
  # See CustomDomain.base_domain and display_domain for details on
  # the difference between display domain and base domain.
  #
  # NOTE: Interally within this class, we try not to use the
  # unqualified term "domain" on its own since there's so much
  # room for confusion.
  #
  #def initialize display_domain, custid
  #  @prefix = :customdomain
  #  @suffix = :object
  #
  #  unless display_domain.is_a?(String)
  #    raise ArgumentError, "Domain must be a string (got #{display_domain.class})"
  #  end
  #
  #  # Set the minimum number of required instance variables,
  #  # where minimum means the ones needed to generate a valid identifier.
  #  @display_domain = display_domain
  #  @custid = custid.to_s
  #
  #  super rediskey, db: self.class.db
  #end
  #
  def init
    # Display domain and cust should already be set and accessible
    # via accessor methods.
    OT.ld "[CustomDomain.init] #{self.display_domain} id:#{self.identifier}"
  end

  # Generate a unique identifier for this customer's custom domain.
  #
  # From a customer's perspective, the display_domain is what they see
  # in their browser's address bar. We use display_domain in the identifier,
  # b/c it's totally reasonable for a user to have multiple custom domains,
  # like secrets.example.com and linx.example.com, and they want to be able
  # to distinguish them from each other.
  #
  # The fact that we rely on this generating the same identifier for a
  # given domain + customer is important b/c it's a means of making
  # sure that the same domain can only be added once per customer.
  #
  # @return [String] A shortened hash of the domain name and custid.
  def derive_id
    if @display_domain.to_s.empty? || @custid.to_s.empty?
      raise OT::Problem, 'Cannot generate identifier with emptiness'
    end
    [@display_domain, @custid].gibbler.shorten
  end

  # Check if the given customer is the owner of this domain
  #
  # @param cust [OT::Customer, String] The customer object or customer ID to check
  # @return [Boolean] true if the customer is the owner, false otherwise
  #def owner?(cust)
  #  (cust.is_a?(OT::Customer) ? cust.custid : cust).eql?(custid)
  #end

  # Destroy the custom domain record
  #
  # Removes the domain identifier from the CustomDomain values
  # and then calls the superclass destroy method
  #
  # @param args [Array] Additional arguments to pass to the superclass destroy method
  # @return [Object] The result of the superclass destroy method
  def delete!(*args)
    OT::CustomDomain.values.rem identifier
    super # we may prefer to call self.clear here instead
  end

  def parse_vhost
    JSON.parse(self.vhost || '{}')
  rescue JSON::ParserError => e
    OT.le "[CustomDomain.parse_vhost] Error #{e}"
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
    if self.identifier.to_s.empty?
      raise RuntimeError, "Identifier cannot be empty for #{self.class}"
    end
  end

  # If we just want to delete the custom domain object key from Redis,
  # we can use the following method: `self.clear`. However, this method
  # runs an atomic MULTI command to delete the key and remove it from the
  # customer's custom domains list. All or nothing.
  def destroy! customer=nil
    redis.multi do |multi|
      multi.del(self.rediskey)
      # Also remove from CustomDomain.values
      multi.zrem(OT::CustomDomain.values.rediskey, identifier)
      unless customer.nil?
        multi.zrem(customer.custom_domains.rediskey, self[:display_domain])
      end
    end
  end

  # Generates a host and value pair for a TXT record.
  #
  # Examples:
  #
  #   _onetime-challenge-domainid -> 7709715a6411631ce1d447428d8a70
  #   _onetime-challenge-domainid.status -> cd94fec5a98fd33a0d70d069acaae9
  #
  def generate_txt_validation_record
    # Include a short identifier that is unique to this domain. This
    # allows for multiple customers to use the same domain without
    # conflicting with each other.
    shortid = self.domainid.to_s[0..6]
    record_host = "#{self.class.txt_validation_prefix}-#{shortid}"

    # Append the TRD if it exists. This allows for multiple subdomains
    # to be used for the same domain.
    # e.g. The `status` in status.example.com.
    unless self.trd.to_s.empty?
      record_host = "#{record_host}.#{self.trd}"
    end

    # The value needs to be sufficiently unique and non-guessable to
    # function as a challenge response. IOW, if we check the DNS for
    # the domain and match the value we've generated here, then we
    # can reasonably assume that the customer controls the domain.
    record_value = SecureRandom.hex(16)

    OT.info "[CustomDomain] Generated txt record #{record_host} -> #{record_value}"

    # These can now be displayed to the customer for them
    # to continue the validation process.
    [record_host, record_value]
  end

  module ClassMethods
    attr_reader :db, :values, :owners, :txt_validation_prefix

    # Returns a Onetime::CustomDomain object after saving it to Redis.
    #
    # +input+ is the domain name that the customer wants to use.
    # +custid+ is the customer ID that owns this domain name.
    #
    # Calls `parse` so it can raise Onetime::Problem.
    def create input, custid
      OT.ld "[CustomDomain.create] Called with #{input} and #{custid}"

      parse(input, custid).tap do |obj|
        OT.ld "[CustomDomain.create] Got #{obj.identifier} #{obj.to_h}"
        self.add obj # Add to CustomDomain.values, CustomDomain.owners

        domainid = obj.identifier

        # Will raise PublicSuffix::DomainInvalid if invalid domain
        ps_domain = PublicSuffix.parse(input, default_rule: nil)
        cust = OT::Customer.new(custid: custid) # don't need to load the customer, just need the rediskey

        OT.info "[CustomDomain.create] Adding domain #{obj.display_domain}/#{domainid} for #{cust}"

        # Add to customer's list of custom domains. It's actually
        # a sorted set so we don't need to worry about dupes.
        cust.add_custom_domain obj

        # See initialize above for more context.
        obj.domainid = obj.identifier
        obj.custid = custid.to_s

        # Store the individual domain parts that PublicSuffix parsed out
        obj.base_domain = ps_domain.domain.to_s
        obj.subdomain = ps_domain.subdomain.to_s
        obj.trd = ps_domain.trd.to_s
        obj.tld = ps_domain.tld.to_s
        obj.sld = ps_domain.sld.to_s

        # Also keep the original input as the customer intended in
        # case there's a need to "audit" this record later on.
        obj._original_value = input

        host, value = obj.generate_txt_validation_record
        obj.txt_validation_host = host
        obj.txt_validation_value = value

        obj.save
      end
    end

    # Returns a Onetime::CustomDomain object (without saving it to Redis).
    #
    # Rescues on the following:
    #   * PublicSuffix::DomainInvalid
    #   * PublicSuffix::DomainNotAllowed
    #   * PublicSuffix::Error (StandardError)
    #
    # Can raise Onetime::Error.
    #
    def parse input, custid
      OT.ld "[CustomDomain.parse] Called with #{input} and #{custid}"

      # The `display_domain` method calls PublicSuffix.parse
      display_domain = OT::CustomDomain.display_domain input

      custom_domain = OT::CustomDomain.new(display_domain, custid)
      OT.ld "[CustomDomain.parse2] Instantiated #{custom_domain.display_domain} and #{custom_domain.custid} (#{display_domain})"
      custom_domain
    end

    # Takes the given input domain and returns the base domain,
    # the one that the zone record would be created for. So
    # froogle.com, www.froogle.com, subdir.www.froogle.com would
    # all return froogle.com here.
    #
    # Another way to think about it, the TXT record we ask the user
    # to create will be created on the base domain. So if we have
    # www.froogle.com, we'll create the TXT record on froogle.com,
    # like this: `_onetime-challenge-domainid.froogle.com`. This is
    # distinct from the domain we ask the user to create an A
    # record for, which is www.froogle.com. We also call this the
    # display domain.
    #
    # Returns either a string or nil if invalid
    def base_domain input
      # We don't need to fuss with empty stripping spaces, prefixes,
      # etc because PublicSuffix does that for us.
      PublicSuffix.domain(input, default_rule: nil)
    end

    # Takes the given input domain and returns the display domain,
    # the one that we ask the user to create an A record for. So
    # subdir.www.froogle.com would return subdir.www.froogle.com here;
    # www.froogle.com would return www.froogle.com; and froogle.com
    # would return froogle.com.
    #
    def display_domain input
      ps_domain = PublicSuffix.parse(input, default_rule: nil)
      ps_domain.subdomain || ps_domain.domain

    rescue PublicSuffix::Error => e
      OT.ld "[CustomDomain.parse] #{e.message} for `#{input}"
      raise Onetime::Problem, e.message
    end

    # Returns boolean, whether the domain is a valid public suffix
    # which checks without actually parsing it.
    def valid? input
      PublicSuffix.valid?(input, default_rule: nil)
    end

    def add fobj
      #self.owners.put fobj.to_s, fobj.custid  # domainid => customer id
      self.values.add OT.now.to_i, fobj.to_s # created time, identifier
    end

    def rem fobj
      self.values.del fobj.to_s
      #self.owners.del fobj.to_s
    end

    def all
      # Load all instances from the sorted set. No need
      # to involve the owners HashKey here.
      self.values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
    end

    def recent duration=48.hours
      spoint, epoint = OT.now.to_i-duration, OT.now.to_i
      self.values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
    end

    # Implement a load method for CustomDomain to make sure the
    # correct derived ID is used as the key.
    def load display_domain, custid
      parse(display_domain, custid).tap do |obj|
        OT.ld "[CustomDomain.load] Got #{obj.identifier} #{obj.to_h}"
        raise OT::Problem, "Domain not found" unless obj.exists?
        from_key(obj.rediskey)
      end
    end
  end

  extend ClassMethods
end
