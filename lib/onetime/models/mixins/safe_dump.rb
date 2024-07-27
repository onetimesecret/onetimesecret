# frozen_string_literal: true


module Onetime::Models
  #
  # SafeDump is a mixin that allows models to define a list of fields that are
  # safe to dump. This is useful for serializing objects to JSON or other
  # formats where you want to ensure that only certain fields are exposed.
  #
  # To use SafeDump, include it in your model and define a list of fields that
  # are safe to dump. The fields can be either symbols or hashes. If a field is
  # a symbol, the method with the same name will be called on the object to
  # retrieve the value. If the field is a hash, the key is the field name and
  # the value is a lambda that will be called with the object as an argument.
  # the hash syntax allows you to:
  #   * define a field name that is different from the method name
  #   * define a field that requires some computation on-the-fly
  #   * define a field that is not a method on the object
  #
  # Example:
  #
  #   @safe_dump_fields = [
  #     :objid,
  #     :updated,
  #     :created,
  #     { :active => ->(obj) { obj.active? } }
  #   ]
  #
  # Internally, all fields are normalized to the hash syntax and store in
  # @safe_dump_field_map. `SafeDump.safe_dump_fields` returns only the list
  # of symbols in the order they were defined. From the example above, it would
  # return `[:objid, :updated, :created, :active]`.
  #
  module SafeDump
    @safe_dump_fields = []
    @safe_dump_field_map = {}

    module ClassMethods

      # `SafeDump.safe_dump_fields` returns only the list
      # of symbols in the order they were defined.
      def safe_dump_fields
        @safe_dump_fields.map do |field|
          field.is_a?(Symbol) ? field : field.keys.first
        end
      end

      # `SafeDump.safe_dump_field_map` returns the field map
      # that is used to dump the fields. The keys are the
      # field names and the values are callables that will
      # expect to receive the instance object as an argument.
      #
      # The map is cached on the first call to this method.
      #
      def safe_dump_field_map
        return @safe_dump_field_map if @safe_dump_field_map.any?

        # Operate directly on the @safe_dump_fields array to
        # build the map. This way we'll get the elements defined
        # in the hash syntax (i.e. since the safe_dump_fields getter
        # method returns only the symbols).
        @safe_dump_field_map = @safe_dump_fields.each_with_object({}) do |el, map|
          if el.is_a?(Symbol)
            field_name = el
            callable = lambda { |obj|
              if obj.respond_to?(:[]) && obj[field_name]
                obj[field_name] # Familia::RedisObject classes
              elsif obj.respond_to?(field_name)
                obj.send(field_name) # Onetime::Models::RedisHash classes via method_missing 😩
              end
            }
          else
            field_name = el.keys.first
            callable = el.values.first
          end
          map[field_name] = callable
        end
      end
    end

    def self.included base
      OT.ld "Including SafeDump in #{base}"
      base.extend ClassMethods

      # Optionally define safe_dump_fields in the class to make
      # sure we always have an array to work with.
      unless base.instance_variable_defined?(:@safe_dump_fields)
        base.instance_variable_set(:@safe_dump_fields, [])
      end

      # Ditto for the field map
      unless base.instance_variable_defined?(:@safe_dump_field_map)
        base.instance_variable_set(:@safe_dump_field_map, {})
      end
    end

    # Returns a hash of safe fields and their values. This method
    # calls the callables defined in the safe_dump_field_map with
    # the instance object as an argument.
    #
    # The return values are not cached, so if you call this method
    # multiple times, the callables will be called each time.
    #
    # Example:
    #
    #   class Customer < Familia::HashKey
    #     include SafeDump
    #     @safe_dump_fields = [
    #       :name,
    #       { :active => ->(cust) { cust.active? } }
    #     ]
    #
    #     def active?
    #       true # or false
    #     end
    #
    #     cust = Customer.new :name => 'Lucy'
    #     cust.safe_dump
    #     #=> { :name => 'Lucy', :active => true }
    #
    def safe_dump
      self.class.safe_dump_field_map.transform_values do |callable|
        transformed_value = callable.call(self)

        # If the value is a relative ancestor of SafeDump we can
        # call safe_dump on it, otherwise we'll just return the value as-is.
        if transformed_value.is_a?(SafeDump)
          transformed_value.safe_dump
        else
          transformed_value
        end
      end
    end

    extend ClassMethods
  end
end
