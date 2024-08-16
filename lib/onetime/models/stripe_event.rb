
class Onetime::StripeEvent < Familia::Horreum
  db 10
  prefix :stripeevent

  feature :safe_dump

  class_sorted_set :values, key: "onetime:stripeevent:values"
  #@values = Familia::SortedSet.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, db: @db

  identifier :secretid

  field :custid
  field :eventid
  field :message_response

  # e.g.
  #
  #  stripe:1234567890:event
  #
  def init
    @prefix = :stripe
    @suffix = :event
    @custid = custid
    @eventid = eventid
    @custid = custid.identifier if custid.is_a?(Familia::RedisObject)
    @eventid = eventid.identifier if eventid.is_a?(Familia::RedisObject)
    @message_response = message_response
  end

  def identifier
    @secretid  # Don't call the method
  end

  def destroy! *args
    super
    # Remove
    OT::StripeEvent.values.rem identifier
  end

  module ClassMethods
    attr_reader :values, :db

    # fobj is a familia object
    def add fobj
      self.values.add OT.now.to_i, fobj.identifier
      self.values.remrangebyscore 0, OT.now.to_i-2.days
    end

    def all
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

    def load fobjid
      fobj = new fobjid
      fobj.exists? ? fobj : nil
    end

    def create(custid, secretid, message_response=nil)
      fobj = new custid, secretid, message_response
      OT.ld "[StripeEvent.create] #{custid} #{secretid} #{message_response}"
      raise ArgumentError, "#{name} record exists #{rediskey}" if fobj.exists?

      fobj.update_fields custid: custid, secretid: secretid, message_response: message_response
      add fobj # to the @values sorted set
      fobj
    end

  end

  extend ClassMethods
end
