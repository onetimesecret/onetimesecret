# apps/api/v2/models/system_settings.rb
#
# frozen_string_literal: true

# System Settings
#
# Representation of the subset of the full YAML configuration that we
# make available to be modified in the colonel. The system settings
# saved in Redis then supercedes the equivalent YAML configuration.
module V2
  class SystemSettings < Familia::Horreum

    using Familia::Refinements::TimeLiterals

    unless defined?(FIELD_MAPPINGS)
      FIELD_MAPPINGS = {
        'interface' => ['site', 'interface'],
        'secret_options' => ['site', 'secret_options'],
        'mail' => ['mail'],
        'limits' => ['limits'],
        'diagnostics' => ['diagnostics'],
      }
    end

    # Fields that need JSON serialization/deserialization
    JSON_FIELDS = FIELD_MAPPINGS.keys.map(&:to_sym).freeze

    class << self
      # Extracts the sections that system settings manages from the full config
      def extract_system_settings(config)
        FIELD_MAPPINGS.transform_values do |path|
          path.length == 1 ? config[path[0]] : config.dig(*path)
        end
      end

      # Returns a hash of only the fields in FIELD_MAPPINGS, with proper deserialization
      def filter_system_settings(config)
        config_data = config.is_a?(Hash) ? config : config.to_h
        FIELD_MAPPINGS.keys.each_with_object({}) do |field, result|
          value = config_data[field]
          # Only include non-empty values
          result[field.to_sym] = value if value && !value.empty?
        end
      end

      # Takes a system settings hash or instance and constructs a new hash
      # with the same structure as the Onetime YAML configuration.
      def construct_onetime_config(config)
        system_settings_hash = config.is_a?(Hash) ? config : config.to_h
        system_settings_hash.transform_keys!(&:to_sym)

        result = {}

        FIELD_MAPPINGS.each do |field, path|
          value = system_settings_hash[field.to_sym]
          # Skip empty/nil values to allow fallback to base config
          next unless value && !value.empty?

          # Build nested hash structure based on path
          current = result
          path[0..-2].each do |key|
            current[key] ||= {}
            current = current[key]
          end
          current[path.last] = value
        end

        result
      end
    end

    feature :safe_dump

    identifier_field :configid

    class_sorted_set :values
    class_sorted_set :stack
    class_sorted_set :audit_log

    field :configid
    # field :interface
    # field :secret_options
    # field :mail
    # field :limits
    # field :diagnostics
    field :custid
    field :comment
    field :created
    field :updated
    field :_original_value

    @txt_validation_prefix = '_onetime-challenge'

    safe_dump_field :identifier, ->(obj) { obj.identifier }
    safe_dump_field :interface
    safe_dump_field :secret_options
    safe_dump_field :mail
    safe_dump_field :limits
    safe_dump_field :diagnostics
    safe_dump_field :custid
    safe_dump_field :comment
    safe_dump_field :created
    safe_dump_field :updated

    def init
      @configid ||= self.generate_id

      OT.ld "[SystemSettings.init] #{configid} #{rediskey}"
    end

    # Serialize complex data to JSON when setting fields
    def serialize_field_value(value)
      if value.is_a?(Hash) || value.is_a?(Array)
        JSON.generate(value)
      else
        value
      end
    end

    # Deserialize JSON strings back to Ruby objects when getting fields
    def deserialize_field_value(field_name, raw_value)
      return nil if raw_value.nil? || raw_value.empty?

      if JSON_FIELDS.include?(field_name.to_sym) && raw_value.is_a?(String)
        begin
          JSON.parse(raw_value)
        rescue JSON::ParserError
          raw_value
        end
      else
        raw_value
      end
    end

    # Override field setters to handle JSON serialization
    JSON_FIELDS.each do |field|
      define_method("#{field}=") do |value|
        serialized_value = serialize_field_value(value)
        instance_variable_set("@#{field}", serialized_value)
      end

      # Override field getters to handle JSON deserialization
      define_method(field) do
        raw_value = instance_variable_get("@#{field}")
        deserialize_field_value(field, raw_value)
      end
    end

    # This method overrides the default save behavior to enforce saving
    # a new record and not updating an existing one. This ensures we
    # have a complete history of configuration objects.
    def save **kwargs
      raise OT::Problem, "Cannot clobber #{self.class} #{rediskey}" if exists?

      redis.multi do |multi|
        super(**kwargs)
        self.class.add(self, multi)
      end
    end

    # Check if the given customer is the owner of this domain
    #
    # @param cust [Onetime::Customer, String] The customer object or customer ID to check
    # @return [Boolean] true if the customer is the owner, false otherwise
    def owner?(cust)
      matching_class = cust.is_a?(Onetime::Customer)
      (matching_class ? cust.custid : cust).to_s.eql?(owner)
    end

    def owner
      custid.to_s
    end

    def to_s
      identifier
    end

    def generate_id
      @key ||= Familia.generate_id.slice(0, 31)
      @key
    end

    def filtered
      # Use the deserialized getter methods
      JSON_FIELDS.each_with_object({}) do |field, result|
        value = send(field) # This now uses the overridden getter
        result[field] = value if value && !value.empty?
      end
    end

    def to_onetime_config
      self.class.construct_onetime_config(filtered)
    end

    # Override to_h to use deserialized values
    def to_h
      JSON_FIELDS.each_with_object({}) do |field, hash|
        value = send(field) # Use the getter method which handles deserialization
        hash[field] = value if value
      end.merge(
        configid: configid,
        custid: custid,
        comment: comment,
        created: created,
        updated: updated
      ).compact
    end

    module ClassMethods
      attr_reader :db, :values, :owners, :txt_validation_prefix

      # Creates a new record
      #
      def create!(**kwargs)
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
            # Use the object's field values which are properly serialized
            kwargs.each do |key, _value|
              # Get the serialized value from the object's instance variable
              serialized_value = obj.instance_variable_get("@#{key}")
              multi.hset(obj.rediskey, key, serialized_value) if serialized_value
            end
            multi.hset(obj.rediskey, :configid, obj.identifier)
            multi.hset(obj.rediskey, :created_at, Familia.now.to_i)
            multi.hset(obj.rediskey, :updated_at, Familia.now.to_i)
            add(obj.identifier, multi) # keep track of instances via class_list :values
          end
        end

        obj  # Return the created object
      rescue Redis::BaseError => e
        OT.le "[SystemSettings.create] Redis error: #{e.message}"
        raise Onetime::Problem, "Unable to create custom domain"
      end


      # Simply instatiates a new SystemSettings object and checks if it exists.
      def exists? identifier
        # The `parse`` method instantiates a new SystemSettings object but does
        # not save it to Redis. We do that here to piggyback on the inital
        # validation and parsing. We use the derived identifier to load
        # the object from Redis using
        obj = load(identifier)
        OT.ld "[SystemSettings.exists?] Got #{obj} for #{identifier}"
        obj.exists?

      rescue Onetime::Problem => e
        OT.le "[SystemSettings.exists?] #{e.message}"
        OT.ld e.backtrace.join("\n")
        false
      end

      def add(fobj, multi = nil)
        now = self.now

        if multi
          # Use the provided multi instance for atomic operations
          multi.zadd(self.instances.rediskey, now, fobj.to_s)
          multi.zadd(self.stack.rediskey, now, fobj.to_s)
          multi.zadd(self.audit_log.rediskey, now, fobj.to_s)
        else
          # Fall back to individual operations for backward compatibility
          self.instances.add fobj.to_s, now
          self.stack.add fobj.to_s, now
          self.audit_log.add fobj.to_s, now
        end
      end

      def rem fobj
        self.instances.remove fobj.to_s
        # don't arbitrarily remove from stack, only for rollbacks/reversions.
        # never remove from audit_log
      end

      def remove_bad_config fobj
        self.instances.remove fobj.to_s
        self.stack.remove fobj.to_s
      end

      def all
        # Load all instances from the sorted set. No need
        # to involve the owners HashKey here.
        self.instances.revrangeraw(0, -1).collect { |identifier| find_by_identifier(identifier) }
      end

      def recent duration=7.days
        spoint, epoint = self.now-duration, self.now
        self.instances.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      def current
        # Get the most recent config by retrieving the element with the highest score
        # (using revrange 0, 0 to get just the highest-scored element)
        objid = self.stack.revrangeraw(0, 0).first
        raise Onetime::RecordNotFound.new("No config stack found") unless objid
        load(objid)
      end

      def previous
        # Get the previous config by retrieving the element with the second-highest score
        # (using revrange 1, 1 to get just the second-highest-scored element)
        objid = self.stack.revrangeraw(1, 1).first
        raise Onetime::RecordNotFound.new("No previous config found") unless objid
        load(objid)
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
        Onetime.hnow # use precision scores
      end
    end

    extend ClassMethods
  end
end
