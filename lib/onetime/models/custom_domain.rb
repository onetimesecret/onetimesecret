
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
  @values = Familia::HashKey.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, db: @db
  @txt_validation_prefix = '_onetime-challenge'

  include Onetime::Models::RedisHash

  #attr_accessor :display_domain, :base_domain, :custid, :subdomain, :tld, :sld, :trd, :_original_value, :txt_validation_host, :txt_validation_value

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
  def initialize display_domain, custid=nil
    unless display_domain.is_a?(String)
      raise ArgumentError, "Domain must be a string"
    end

    super name, db: self.class.db # `name` here refers to `RedisHash#name`

    # WARNING: There's a gnarly bug in the awkward relationship between
    # RedisHash (local lib) and RedisObject (familia gem) where a value
    # can be set to an instance var, the in-memory cache in RedisHash,
    # and/or the persisted value in redis. RedisHash#method_missing
    # allows for calling fields as method names on the object itself;
    # RedisObject (specifically Familia::HashKey in this case), relies
    # on `[]` and `[]=` to access and set values in redis.
    #
    # The problem is that the value set by RedisHash#method_missing
    # is not available to RedisObject (Familia::HashKey) until after
    # the object has been initialized and `super` called in RedisObject.
    # Long story short: we set these two instance vars do that the
    # identifier method can produce a valid identifier string. But,
    # we're relying on CustomDomain.create to duplicate the effort
    # and set the same values in the way that will persist them to
    # redis. Hopefully I do'nt find myself reading this comment in
    # 5 years and wondering why I can't just call `super` man.
    @display_domain = display_domain
    @custid = custid
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
    return nil if @custid.nil?
    [@display_domain, @custid].gibbler.shorten
  end
  alias :domainid :identifier

  def save(*)
    raise ArgumentError, "No customer id provided" unless @custid
    super # pass the arguments on as-is
  end

  # Check if the given customer is the owner of this domain
  #
  # @param cust [OT::Customer, String] The customer object or customer ID to check
  # @return [Boolean] true if the customer is the owner, false otherwise
  def owner?(cust)
    (cust.is_a?(OT::Customer) ? cust.custid : cust).eql?(custid)
  end

  # Destroy the custom domain record
  #
  # Removes the domain identifier from the CustomDomain values
  # and then calls the superclass destroy method
  #
  # @param args [Array] Additional arguments to pass to the superclass destroy method
  # @return [Object] The result of the superclass destroy method
  def destroy!(*args)
    OT::CustomDomain.values.rem identifier
    super
  end

  module ClassMethods
    attr_reader :db, :values, :txt_validation_prefix

    # Returns a Onetime::CustomDomain object after saving it to Redis.
    #
    # Calls `parse` so it can raise Onetime::Problem.
    def create input, custid
      parse(input, custid).tap do |obj|
        domainid = obj.identifier

        ps_domain = PublicSuffix.parse(input, default_rule: nil)  # raises PublicSuffix::DomainInvalid if invalid domain

        OT.info "[CustomDomain.create] Adding domain #{obj.display_domain}/#{domainid} for #{custid}"

        # This looks like a tautology but it's actually doing something
        # you'd expect was already taken care of: making sure that the
        # display domain field is persisted to Redis.
        #
        # See initialize above for more context.
        obj[:display_domain] = obj.display_domain
        obj[:custid] = custid

        # Store the individual domain parts that PublicSuffix parsed out
        obj[:base_domain] = ps_domain.domain
        obj[:subdomain] = ps_domain.subdomain
        obj[:trd] = ps_domain.trd
        obj[:tld] = ps_domain.tld
        obj[:sld] = ps_domain.sld

        # Also keep the original input as the customer intended in
        # case there's a need to "audit" this record later on.
        obj[:_original_value] = input

        obj.save

        host, value = generate_txt_validation_record(obj)
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
    def parse input, custid=nil
      # The `display_domain` method calls PublicSuffix.parse
      display_domain = OT::CustomDomain.display_domain input

      OT::CustomDomain.new(display_domain, custid)
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
      shortid = obj.domainid.to_s[0..6]
      record_host = "#{txt_validation_prefix}-#{shortid}"

      # Append the TRD if it exists. This allows for multiple subdomains
      # to be used for the same domain.
      # e.g. The `status` in status.example.com.
      unless obj.trd.to_s.empty?
        record_host = "#{record_host}.#{obj.trd}"
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
  end

  extend ClassMethods
end
