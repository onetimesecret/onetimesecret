# apps/api/v2/models/mutable_config.rb

# Mutable Configuration
#
# Representation of the subset of the full YAML configuration that we
# make available to be modified in the colonel. The mutable config
# saved in Redis then supercedes the equivalent YAML configuration.
module V2
  class MutableConfig < Familia::Horreum

    JSON_FIELDS = [
      :ui,
      :api,
      :secret_options,
      :mail,
      :limits,
    ].freeze

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

    @safe_dump_fields = [
      { identifier: ->(obj) { obj.identifier } },
      :ui,
      :secret_options,
      :api,
      :mail,
      :limits,
      :custid,
      :comment,
      :created,
      :updated,
    ].freeze

    def init
      @configid ||= generate_id

      OT.ld "[MutableConfig.init] #{configid} #{rediskey}"
    end

    # This method overrides the default save behavior to enforce saving
    # a new record and not updating an existing one. This ensures we
    # have a complete history of configuration objects.
    def save(**)
      raise OT::Problem, "Cannot clobber #{self.class} #{rediskey}" if exists?

      redis.multi do |multi|
        super(**)
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

    require_relative 'mixins/comments'
    include V2::Mixins::ModelComments
  end
end

require_relative 'mutable_config/class_methods'
