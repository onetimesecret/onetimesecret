# apps/api/v2/models/mutable_config/class_methods.rb

# Mutable Config model - Class Methods
#
module V2
  class MutableConfig < Familia::Horreum

    module ClassMethods
      attr_reader :db, :values, :owners

      # Creates a new record
      #
      def create(**kwargs)
        obj = new(**kwargs)

        # Fail fast if invalid fields are provided
        kwargs.each_with_index do |(key, _value), index|
          next if fields.include?(key.to_s.to_sym) # Familia uses symbols

          raise Onetime::Problem, "Invalid field #{key} (#{index})"
        end

        redis.watch(obj.rediskey) do
          if obj.exists?
            redis.unwatch
            raise Onetime::Problem, "Duplicate record #{obj.rediskey}"
          end

          redis.multi do |multi|
            # Use the object's field values which are properly serialized
            kwargs.each do |key, _value|
              # Get the serialized value from the object's instance variable
              serialized_value = obj.instance_variable_get("@#{key}")
              multi.hset(obj.rediskey, key, serialized_value) if serialized_value
            end
            multi.hset(obj.rediskey, :configid, obj.identifier)
            multi.hset(obj.rediskey, :created_at, Time.now.to_i)
            multi.hset(obj.rediskey, :updated_at, Time.now.to_i)
            add(obj.identifier, multi) # keep track of instances via class_list :values
          end
        end

        obj  # Return the created object
      rescue Redis::BaseError => ex
        OT.le "[MutableConfig.create] Redis error: #{ex.message}"
        raise Onetime::Problem, 'Unable to create custom domain'
      end

      # Simply instatiates a new MutableConfig object and checks if it exists.
      def exists?(identifier)
        # The `parse`` method instantiates a new MutableConfig object but does
        # not save it to Redis. We do that here to piggyback on the inital
        # validation and parsing. We use the derived identifier to load
        # the object from Redis using
        obj = load(identifier)
        OT.ld "[MutableConfig.exists?] Got #{obj} for #{identifier}"
        obj.exists?
      rescue Onetime::Problem => ex
        OT.le "[MutableConfig.exists?] #{ex.message}"
        OT.ld ex.backtrace.join("\n")
        false
      end

      def add(fobj, multi = nil)
        now = self.now

        if multi
          # Use the provided multi instance for atomic operations
          multi.zadd(values.rediskey, now, fobj.to_s)
          multi.zadd(stack.rediskey, now, fobj.to_s)
          multi.zadd(audit_log.rediskey, now, fobj.to_s)
        else
          # Fall back to individual operations for backward compatibility
          values.add now, fobj.to_s
          stack.add now, fobj.to_s
          audit_log.add now, fobj.to_s
        end
      end

      def rem(fobj)
        values.remove fobj.to_s
        # don't arbitrarily remove from stack, only for rollbacks/reversions.
        # never remove from audit_log
      end

      def remove_bad_config(fobj)
        values.remove fobj.to_s
        stack.remove fobj.to_s
      end

      def all
        # Load all instances from the sorted set. No need
        # to involve the owners HashKey here.
        values.revrangeraw(0, -1).collect { |identifier| from_identifier(identifier) }
      end

      def recent(duration = 7.days)
        spoint = now-duration
        epoint = now
        values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      def current
        # Get the most recent config by retrieving the element with the highest score
        # (using revrange 0, 0 to get just the highest-scored element)
        objid = stack.revrangeraw(0, 0).first
        raise Onetime::RecordNotFound.new('No config stack found') unless objid

        load(objid)
      end

      def previous
        # Get the previous config by retrieving the element with the second-highest score
        # (using revrange 1, 1 to get just the second-highest-scored element)
        objid = stack.revrangeraw(1, 1).first
        raise Onetime::RecordNotFound.new('No previous config found') unless objid

        load(objid)
      end

      def rollback!
        rollback_key = rediskey(:rollback)
        redis.watch(rollback_key) do
          redis.multi do |multi|
            multi.zpopmax(stack.rediskey, 1).first&.first
            multi.revrangeraw(0, 0).first
          end

          OT.li "[#{self} removed #{removed_identifier}; current is #{current_identifier}]"
        end
      end

      def history
        history.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end

      # Using precision time (float) is critical for sorted set scores because it ensures
      # proper ordering of configuration records in chronological sequence. Without
      # precision, multiple configs created within the same second would have identical
      # integer scores, making their order in the sorted set non-deterministic.
      #
      # This precise ordering is essential for:
      # - current: Finding the most recent config reliably
      # - previous: Identifying the correct second-most-recent config for rollbacks
      # - rollback!: Ensuring we remove the actual latest config, not an arbitrary one
      #
      # Float timestamps provide microsecond precision, virtually eliminating the
      # possibility of score collisions even with rapid sequential operations.
      def now
        OT.hnow # use precision scores
      end
    end

    extend ClassMethods
  end
end
