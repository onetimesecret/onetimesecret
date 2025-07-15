# apps/api/v2/models/mutable_config.rb

# Mutable Configuration
#
# Representation of the subset of the full YAML configuration that we
# make available to be modified in the colonel. The mutable config
# saved in Redis then supercedes the equivalent YAML configuration.
module V2
  class MutableConfig < Familia::Horreum
    include Gibbler::Complex

    # The top-level mutable config mapped to their equivalents in
    # the old YAML format (<v0.23.0).
    unless defined?(FIELD_MAPPINGS)
      FIELD_MAPPINGS = {
        ui: [:site, :interface, :ui],
        secret_options: [:site, :secret_options],
        mail: [:mail],
        limits: [:limits],
        api: [:site, :interface, :api],
      }.freeze
    end

    # Fields that need JSON serialization/deserialization
    JSON_FIELDS = FIELD_MAPPINGS.keys.freeze

    feature :safe_dump

    identifier :configid

    class_sorted_set :values
    class_sorted_set :stack
    class_sorted_set :audit_log

    field :configid
    field :ui
    field :api
    field :secret_options
    field :mail
    field :limits
    field :features
    field :custid
    field :comment
    field :created
    field :updated
    field :_original_value

    @txt_validation_prefix = '_onetime-challenge'.freeze

    @safe_dump_fields = [
      { identifier: ->(obj) { obj.identifier } },
      :ui,
      :secret_options,
      :api,
      :mail,
      :limits,
      :features,
      :custid,
      :comment,
      :created,
      :updated,
    ].freeze

    def init
      @configid ||= generate_id

      OT.ld "[MutableConfig.init] #{configid} #{rediskey}"
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
    # @param cust [V2::Customer, String] The customer object or customer ID to check
    # @return [Boolean] true if the customer is the owner, false otherwise
    def owner?(cust)
      matching_class = cust.is_a?(V2::Customer)
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
        value         = send(field) # This now uses the overridden getter
        result[field] = value if value && !value.empty?
      end
    end

    # def to_onetime_config
    #   self.class.construct_onetime_config(filtered)
    # end

    # Override to_h to use deserialized values
    # def to_h
    #   JSON_FIELDS.each_with_object({}) do |field, hash|
    #     value       = send(field) # Use the getter method which handles deserialization
    #     hash[field] = value if value
    #   end.merge(
    #     configid: configid,
    #     custid: custid,
    #     comment: comment,
    #     created: created,
    #     updated: updated,
    #   ).compact
    # end

    class << self
      # Extracts the sections that mutable config manages from the full
      # single-file config (i.e. old format). this can still be useful in
      # future if we want to have a convertor around for a while to allow
      # for migrations to v0.23+.
      def extract_mutable_config(config)
        FIELD_MAPPINGS.transform_values do |path|
          path.length == 1 ? config[path[0]] : config.dig(*path)
        end
      end

      # Takes a mutable config hash or instance and constructs a new hash
      # with the same structure as the Onetime YAML configuration.
      #
      # TODO: Remove on account of having the new config operational
      def construct_onetime_config(config)
        mutable_config_hash = config.is_a?(Hash) ? config : config.to_h
        mutable_config_hash.transform_keys!(&:to_sym)

        result = {}

        FIELD_MAPPINGS.each do |field, path|
          value = mutable_config_hash[field]
          # Skip empty/nil values to allow fallback to base config
          next unless value && !value.empty?

          # Build nested hash structure based on path
          current            = result
          path[0..-2].each do |key|
            current[key] ||= {}
            current        = current[key]
          end
          current[path.last] = value
        end

        result
      end
    end

    require_relative 'mixins/comments'
    include V2::Mixins::ModelComments
  end
end

require_relative 'mutable_config/class_methods'
