# apps/api/v1/models/splittest.rb

# An example of a session method to create groups.
#
#  def session_group groups
#    sessid.to_i(16) % groups.to_i
#  end

module V1
  class SplitTest < Familia::Horreum

    feature :safe_dump
    feature :expiration

    @tests = {}

    attr_accessor :values

    def initialize testname=nil
      @testname = testname
      super name, db: 1, ttl: 30.days
    end

    def register_visitor!
      sample_count = increment(:samples)
      group_idx = sample_count % values.size
    end

    def sample! group_idx
      if group_idx >= values.size || group_idx < 0
        raise RuntimeError, "group_idx must be within the range of available groups"
      end
      counter_key = Familia.join :counter, self.class.quantize(OT.now, 1.day).to_i, group_idx
      increment counter_key
      group_values group_idx
    end

    def group_values idx
      values[idx]
    end

    def testname= sid
      @testname = sid
      @name = name
      @testname
    end

    def identifier
      @testname  # Don't call the method
    end

    module ClassMethods
      attr_reader :tests

      def quantize(stamp, quantum)
        stamp = stamp.is_a?(Integer) ? stamp : stamp.to_i
        stamp - (stamp % quantum)
      end

      def from_config conf
        conf ||= {}
        conf.each_pair do |name,groups|
          groups.collect! { |v| [v].flatten }
          OT.info "Split test #{name}: #{groups.inspect}"
          register_test name.to_s, *groups
        end
      end

      def register_test name, *values
        tests[name.to_s] = create(name, *values)
      end

      def test_running? testname
        V1::SplitTest.tests.has_key?(testname.to_s)
      end

      def method_missing meth, *args
        test = tests[meth.to_s]
        raise NoMethodError, meth.to_s if test.nil?
        test
      end

      #def exists? objid
      #  obj = new
      #  obj.testname = objid
      #  obj.exists?
      #end

      def create testname, *values
        obj = new testname
        # force the storing of the fields to redis
        obj.testname, obj.values = testname, values
        obj.save
        obj
      end
    end

    extend ClassMethods
  end
end
