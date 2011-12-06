

class Onetime::SplitTest < Familia::HashKey
  include Onetime::Models::RedisHash
  @tests = {}
  attr_accessor :values
  def initialize testname=nil
    @testname = testname
    super name, :db => 1, :ttl => 30.days
  end
  class << self
    attr_reader :tests
    def from_config conf
      conf ||= {}
      conf.each_pair do |name,values|
        OT.ld "Split test #{name}: #{values}"
        register_test name.to_s, *values
      end
    end
    def register_test name, *values
      tests[name] = create(name, *values)
    end
    def exists? objid
      obj = new 
      obj.testname = objid
      obj.exists?
    end
    def load objid
      obj = new 
      obj.testname = objid
      obj.exists? ? obj : nil
    end
    def create testname, *values
      obj = new testname
      # force the storing of the fields to redis
      obj.testname, obj.values = testname, values.flatten.compact
      obj.save
      obj
    end
  end
  def method_missing meth, *args
    test = self.class.tests[meth.to_s]
    super if test.nil?
    test
  end
  def sample!
    cnt = increment :samples
    counter_key = Familia.join :counter, OT.now.quantize(1.day).to_i
    increment counter_key
  end
  def testname= sid
    @testname = sid
    @name = name
    @testname
  end
  def identifier
    @testname  # Don't call the method
  end
end
