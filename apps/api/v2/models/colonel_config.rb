# apps/api/v2/models/colonel_config.rb

# Colonel Config
#
# Representation of the subset of the full YAML configuration that we
# make available to be modified in the colonel. The colonel config
# saved in Redis then supercedes the equivalent YAML configuration.
module V2
  class ColonelConfig < Familia::Horreum
    include Gibbler::Complex

    feature :safe_dump

    identifier :configid

    class_sorted_set :values
    class_hashkey :history

    field :configid
    field :interface
    field :secret_options
    field :mail
    field :limits
    field :experimental
    field :diagnostics
    field :custid
    field :comment
    field :created
    field :updated
    field :_original_value

    hashkey :brand
    hashkey :logo # image fields need a corresponding v2 route and logic class
    hashkey :icon

    @txt_validation_prefix = '_onetime-challenge'

    @safe_dump_fields = [
      { :identifier => ->(obj) { obj.identifier } },
      :interface,
      :secret_options,
      :mail,
      :limits,
      :experimental,
      :diagnostics,
      :custid,
      :comment,
      :created,
      :updated,
    ]

    def init
      @configid ||= self.generate_id

      OT.ld "[ColonelConfig.init] id:#{configid}"
    end

    # This method overrides the default save behavior to enforce saving
    # a new record and not updating an existing one. This ensures we
    # have a complete history of configuration objects.
    def save **kwargs
      raise OT::Problem, "Cannot clobber #{self.class} #{rediskey}" if exists?
      super(**kwargs)
    end

    # Check if the given customer is the owner of this domain
    #
    # @param cust [V2::Customer, String] The customer object or customer ID to check
    # @return [Boolean] true if the customer is the owner, false otherwise
    def owner?(cust)
      matching_class = cust.is_a?(V2::Customer)
      (matching_class ? cust.custid : cust).eql?(custid)
    end

    def generate_id
      @key ||= Familia.generate_id.slice(0, 31)
      @key
    end

    module ClassMethods
      attr_reader :db, :values, :owners, :txt_validation_prefix

      # Creates a new record
      #
      def create(**kwargs)
        obj = new(**kwargs)

        # Fail fast if invalid fields are provided
        kwargs.each_with_index do |(key, value), index|
          next if self.fields.include?(key.to_s.to_sym)
          raise Onetime::Problem, "Invalid field #{key} (#{index})"
        end

        redis.watch(obj.rediskey) do
          if obj.exists?
            redis.unwatch
            raise Onetime::Problem, "Duplicate record #{obj.rediskey}"
          end

          redis.multi do |multi|
            # We're using multi here instead of save to ensure atomicity
            kwargs.each_with_index do |(key, value), index|
              multi.hset(obj.rediskey, key, value.to_s)
            end
            multi.hset(obj.rediskey, :configid, obj.identifier)
            multi.hset(obj.rediskey, :created_at, Time.now.to_i)
            multi.hset(obj.rediskey, :updated_at, Time.now.to_i)
            add(obj.identifier) # keep track of instances via class_list :values
          end
        end

        obj  # Return the created object
      rescue Redis::BaseError => e
        OT.le "[ColonelConfig.create] Redis error: #{e.message}"
        raise Onetime::Problem, "Unable to create custom domain"
      end

      # Simply instatiates a new ColonelConfig object and checks if it exists.
      def exists? identifier
        # The `parse`` method instantiates a new ColonelConfig object but does
        # not save it to Redis. We do that here to piggyback on the inital
        # validation and parsing. We use the derived identifier to load
        # the object from Redis using
        obj = load(identifier)
        OT.ld "[ColonelConfig.exists?] Got #{obj} for #{identifier}"
        obj.exists?

      rescue Onetime::Problem => e
        OT.le "[ColonelConfig.exists?] #{e.message}"
        OT.ld e.backtrace.join("\n")
        false
      end

      def add fobj
        now = OT.now.to_i # created time, identifier
        self.values.add now, fobj.to_s
        self.stack.add now, fobj.to_s
      end

      def rem fobj
        self.values.remove fobj.to_s
        # don't arbitrarily remove from stack, only for rollbacks/reversions.
        # never remove from audit_log
      end

      def all
        # Load all instances from the sorted set. No need
        # to involve the owners HashKey here.
        self.values.revrangeraw(0, -1).collect { |identifier| from_identifier(identifier) }
      end

      def recent duration=7.days
        spoint, epoint = OT.now.to_i-duration, OT.now.to_i
        self.values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      def current
        # Get the most recent config by retrieving the element with the highest score
        # (using revrange 0, 0 to get just the highest-scored element)
        latest_identifier = self.stack.revrangeraw(0, 0).first
        raise Onetime::Problem.new("No config stack found") unless latest_identifier
        load(latest_identifier)
      end

      def previous
        # Get the previous config by retrieving the element with the second-highest score
        # (using revrange 1, 1 to get just the second-highest-scored element)
        previous_identifier = self.stack.revrangeraw(1, 1).first
        raise Onetime::Problem.new("No previous config found") unless previous_identifier
        load(previous_identifier)
      end

      def rollback!
        rollback_key = rediskey(:rollback)
        redis.watch(rollback_key) do

          redis.multi do |multi|
            removed_identifier = multi.zpopmax(self.stack.rediskey, 1).first&.first
            current_identifier = multi.revrangeraw(0, 0).first
          end

          OT.li "[#{self} removed #{removed_identifier}; current is #{current_identifier}]"
        end
      end

      def history
        self.history.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end
    end

    extend ClassMethods
  end
end
