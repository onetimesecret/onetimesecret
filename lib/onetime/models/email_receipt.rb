
class Onetime::EmailReceipt < Familia::HashKey
  include Onetime::Models::RedisHash

  # e.g.
  #
  #  secret:1234567890:email
  #
  @values = Familia::HashKey.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, db: 10

  attr_accessor :values

  def initialize custid=nil, sessid=nil, secretid=nil
    @prefix = :secret
    @suffix = :email
    @custid, @sessid, @secretid = custid.to_s, sessid.to_s, secretid.to_s
    super name, db: 10
  end

  def identifier
    @secretid  # Don't call the method
  end

  def destroy! *args
    super
    # Remove
    OT::EmailReceipt.values.rem identifier
  end

  module ClassMethods
    attr_reader :values
    def add fobj  # familia object
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

    def create(custid, sessid, secretid)
      fobj = new custid, sessid, secretid
      raise ArgumentError, "#{name} record exists for secret #{secretid}" if fobj.exists?
      fobj.update_fields custid: custid, sessid: sessid, secret: secretid
      add fobj # to the @values sorted set
      fobj
    end

    #def generate_id *entropy
    #  entropy << OT.entropy
    #  input = [OT.instance, OT.now.to_f, :session, *entropy].join(':')
    #  # Not using gibbler to make sure it's always SHA512
    #  Digest::SHA512.hexdigest(input).to_i(16).to_s(36) # base-36 encoding
    #end
  end

  extend ClassMethods
end
