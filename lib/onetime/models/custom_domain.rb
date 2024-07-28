
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

class Onetime::CustomDomain < Familia::HashKey
  @db = 6
  # NOTE: The redis key used by older models for values is simply
  # "onetime:customdomain". We'll want to rename those at some point.
  @values = Familia::SortedSet.new [name.to_s.downcase.gsub('::', Familia.delim).to_sym, :values], db: @db
  #@owners = Familia::HashKey.new [name.to_s.downcase.gsub('::', Familia.delim).to_sym, :owners], db: @db
  @txt_validation_prefix = '_onetime-challenge'

  @safe_dump_fields = [
    :domainid,
    :custid,
    :display_domain,
    :base_domain,
    :subdomain,
    :trd,
    :tld,
    :sld,
    :_original_value,
    :txt_validation_host,
    :txt_validation_value,
    :status,
    :verified,
    :created,
    :updated
  ]

  include Onetime::Models::SafeDump

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
  # WARNING: A feature/limitation of Familia RedisObjects is that all
  # arguments to initialize must be named arguments. This is because
  # up the `super` chain, we're expecting a catch-all argument named
  # `opts`. If opts is nil, all hell breaks loose and we get an error.
  #
  # See RedisObject#initialize. It's possible thise could be addressed.
  # Actually it's possible that we just need to run super before setting
  # the instance variables.
  #
  def initialize display_domain, custid
    @prefix = :customdomain
    @suffix = :object

    unless display_domain.is_a?(String)
      raise ArgumentError, "Domain must be a string (got #{display_domain.class})"
    end

    # Set the minimum number of required instance variables,
    # where minimum means the ones needed to generate a valid identifier.
    @display_domain = display_domain
    @custid = custid.to_s

    super rediskey, db: self.class.db
  end

  def init
    self[:display_domain] = @display_domain
    self[:custid] = @custid
    OT.ld "[CustomDomain.init] #{self[:display_domain]} id:#{identifier}"
  end

  def rediskey
    @prefix ||= self.class.to_s.downcase.split('::').last.to_sym
    @suffix ||= :object
    Familia.rediskey @prefix, self.identifier, @suffix
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
  def identifier
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
  def del(*args)
    OT::CustomDomain.values.rem identifier
    super # we may prefer to call self.clear here instead
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

  def update_fields hsh={}
    check_identifier!
    hsh[:updated] = OT.now.to_i
    hsh[:created] = OT.now.to_i unless has_key?(:created)
    update hsh # See Familia::RedisObject#update
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
        multi.zrem(customer.custom_domains_list.rediskey, self[:display_domain])
      end
    end
  end

  module ClassMethods
    attr_reader :db, :values, :owners, :txt_validation_prefix

    # Returns a Onetime::CustomDomain object after saving it to Redis.
    #
    # Calls `parse` so it can raise Onetime::Problem.
    def create input, custid
      OT.ld "[CustomDomain.create] Called with #{input} and #{custid}"

      parse(input, custid).tap do |obj|
        OT.ld "[CustomDomain.tap] Got #{obj.all} #{obj.all}"
        self.add obj # Add to CustomDomain.values, CustomDomain.owners

        domainid = obj.identifier

        # Will raise PublicSuffix::DomainInvalid if invalid domain
        ps_domain = PublicSuffix.parse(input, default_rule: nil)
        cust = OT::Customer.new(custid)

        p [5, obj[:display_domain], obj[:domainid]]
        OT.info "[CustomDomain.create] Adding domain #{obj["display_domain"]}/#{domainid} for #{cust}"

        # Add to customer's list of custom domains. It's actually
        # a sorted set so we don't need to worry about dupes.
        cust.add_custom_domain obj

        # See initialize above for more context.
        hsh = {}
        hsh[:domainid] = obj.identifier
        hsh[:custid] = custid.to_s

        # Store the individual domain parts that PublicSuffix parsed out
        hsh[:base_domain] = ps_domain.domain.to_s
        hsh[:subdomain] = ps_domain.subdomain.to_s
        hsh[:trd] = ps_domain.trd.to_s
        hsh[:tld] = ps_domain.tld.to_s
        hsh[:sld] = ps_domain.sld.to_s

        # Also keep the original input as the customer intended in
        # case there's a need to "audit" this record later on.
        hsh[:_original_value] = input

        host, value = generate_txt_validation_record(hsh)
        hsh[:txt_validation_host] = host
        hsh[:txt_validation_value] = value

        obj.update_fields hsh
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
      OT.ld "[CustomDomain.parse2] Instantiated #{custom_domain[:display_domain]} and #{custom_domain[:custid]} (#{display_domain})"
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
    # distinct from the domain we ask the user to create a CNAME
    # record on, which is www.froogle.com. We also call this the
    # display domain.
    #
    # Returns either a string or nil if invalid
    def base_domain input
      # We don't need to fuss with empty stripping spaces, prefixes,
      # etc because PublicSuffix does that for us.
      PublicSuffix.domain(input, default_rule: nil)
    end

    # Takes the given input domain and returns the display domain,
    # the one that we ask the user to create a CNAME record on. So
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

    # Generates a host and value pair for a TXT record.
    #
    # Examples:
    #
    #   _onetime-challenge-domainid -> 7709715a6411631ce1d447428d8a70
    #   _onetime-challenge-domainid.status -> cd94fec5a98fd33a0d70d069acaae9
    #
    def generate_txt_validation_record obj
      # Include a short identifier that is unique to this domain. This
      # allows for multiple customers to use the same domain without
      # conflicting with each other.
      shortid = obj[:domainid].to_s[0..6]
      record_host = "#{txt_validation_prefix}-#{shortid}"

      # Append the TRD if it exists. This allows for multiple subdomains
      # to be used for the same domain.
      # e.g. The `status` in status.example.com.
      unless obj[:trd].to_s.empty?
        record_host = "#{record_host}.#{obj[:trd]}"
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

    def add fobj
      #self.owners.put fobj.to_s, fobj[:custid]  # domainid => customer id
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

    def exists? fobjid
      fobj = new fobjid
      fobj.exists?
    end

    def load display_domain, custid
      OT.ld "[CustomDomain.load] Got #{display_domain} and #{custid}"
      # Seems weird at first blush that we're just instantiating
      # and checking whether the object key exists in Redis, that
      # we're not also loading all of the attributes. But at second
      # blush it makes sense b/c it's equivalent to lazy loading
      # which is a common pattern. Whether lazy loading presents
      # much value or not when working with redis (which is already
      # a fast, in-memory data store) is a different question.
      fobj = new display_domain, custid
      fobj.exists? ? fobj : nil
      #
      #      key = Familia.join(:customdomain, fobjid, :object)
      #      redis = Familia.redis(db)
      #      robj = redis.hgetall key
      #      new robj['display_domain'], robj['custid']
    end
  end

  extend ClassMethods
end
