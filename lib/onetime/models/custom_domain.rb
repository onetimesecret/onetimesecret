
# Custom Domain
#
# Every customer can have one or more custom domains.
#
# The list of custom domains that are associated to a customer is
# distinct from a customer's subdomain.
#

require 'public_suffix'

class Onetime::CustomDomain < Familia::HashKey
  @db = 6
  @values = Familia::HashKey.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, db: @db

  include Onetime::Models::RedisHash

  def initialize domain=nil, custid=nil
    @prefix, @suffix = :custom_domain, :object
    @domain = OT::CustomDomain.normalize(domain)
    @custid = custid
    super name, db: self.class.db
  end

  def identifier
    @domain.gibbler.shorten
  end

  def owner? cust
    (cust.is_a?(OT::Customer) ? cust.custid : cust).eql?(custid)
  end

  def destroy! *args
    OT::CustomDomain.values.rem identifier
    super
  end

  module ClassMethods
    attr_reader :db, :values

    # Returns a Onetime::CustomDomain object (without saving it to Redis).
    #
    # Rescues on the following:
    #   * PublicSuffix::DomainInvalid
    #   * PublicSuffix::DomainNotAllowed
    #   * PublicSuffix::Error (StandardError)
    #
    # Can raise Onetime::Error.
    #
    def parse name
      ps_domain = PublicSuffix.parse(name, default_rule: nil)
      OT::CustomDomain.new(ps_domain.domain)
    rescue PublicSuffix::Error => e
      OT.ld "[CustomDomain.parse] #{e.message} for `#{name}"
      raise Onetime::Problem, e.message
    end

    # Returns a Onetime::CustomDomain object after saving it to Redis.
    #
    # Calls `parse` so it can raise Onetime::Problem.
    def create name=nil, custid=nil
      parse(name).tap do |cd|
        cd.custid = custid if custid
        OT.info "[CustomDomain.create] Added domain #{name} for #{custid}"
        cd.save
      end
    end

    # Returns either a string or nil if invalid
    def normalize name
      # We don't need to fuss with empty stripping spaces, prefixes,
      # etc because PublicSuffix does that for us.
      PublicSuffix.domain(name, default_rule: nil)
    end

    # Returns boolean, whether the domain is a valid public suffix
    # which checks without actually parsing it.
    def valid? name
      PublicSuffix.valid?(name, default_rule: nil)
    end
  end

  extend ClassMethods
end
