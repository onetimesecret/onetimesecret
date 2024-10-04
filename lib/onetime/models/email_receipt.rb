
class Onetime::EmailReceipt < Familia::Horreum
  include Gibbler::Complex

  feature :safe_dump
  feature :expiration

  db 8
  ttl 14.days

  prefix :secret
  identifier :secretid
  suffix :email

  class_sorted_set :values, key: 'onetime:emailreceipt'

  field :secretid
  field :custid
  field :message_response
  field :created
  field :updated

  # e.g.
  #
  #  secret:1234567890:email
  #
  #def initialize custid=nil, secretid=nil, message_response=nil
  #  @prefix = :secret
  #  @suffix = :email
  #  @custid = custid
  #  @secretid = secretid
  #  @custid = custid.identifier if custid.is_a?(Familia::RedisObject)
  #  @secretid = secretid.identifier if secretid.is_a?(Familia::RedisObject)
  #  @message_response = message_response
  #  super name, db: 8, ttl: 30.days
  #end

  def destroy! *args
    super
    # Remove
    OT::EmailReceipt.values.rem identifier
  end

  module ClassMethods
    attr_reader :values

    # fobj is a familia object
    def add fobj
      self.values.add OT.now.to_i, fobj.identifier
      self.values.remrangebyscore 0, OT.now.to_i-14.days # keep 14 days of email activity
    end

    def all
      self.values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
    end

    def recent duration=48.hours
      spoint, epoint = OT.now.to_i-duration, OT.now.to_i
      self.values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
    end

    def create(custid, secretid, message_response=nil)
      fobj = new secretid: secretid, custid: custid, message_response: message_response
      OT.ld "[EmailReceipt.create] #{custid} #{secretid} #{message_response}"
      raise ArgumentError, "#{name} record exists #{fobj.rediskey}" if fobj.exists?

      fobj.apply_fields custid: custid, secretid: secretid, message_response: message_response
      fobj.save
      add fobj # to the @values sorted set
      fobj
    end

  end

  extend ClassMethods
end
