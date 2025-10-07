# lib/onetime/models/customer/features/deprecated_fields.rb

module Onetime::Customer::Features
  module DeprecatedFields
    Familia::Base.add_feature self, :deprecated_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      base.field_group :deprecated_fields do
        base.field :sessid
        base.field :apitoken # TODO: use sorted set?
        base.field :contributor
      end
    end

    module ClassMethods
      # Use Familia 2's generated class methods
      # def add(cust)
      #   values.add cust.identifier, OT.now.to_i
      # end

      def all
        values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
      end

      def recent(duration = 30.days, epoint = OT.now.to_i)
        spoint = OT.now.to_i - duration
        values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
      end

      # Generate a unique session ID with 32 bytes of random data
      # @return [String] base-36 encoded random string
      def generate_id
        OT::Utils.generate_id
      end
    end

    module InstanceMethods
      def locale?
        !locale.to_s.empty?
      end

      def apitoken?(guess)
        apitoken.to_s == guess.to_s
      end

      def regenerate_apitoken
        apitoken! Familia.generate_id
        apitoken # the fast writer bang methods don't return the value
      end

      def external_identifier
        raise OT::Problem, 'Anonymous customer has no external identifier' if anonymous?

        @external_identifier ||= Familia.generate_id # generate but don't save
        @external_identifier
      end

      def global?
        custid.to_s.eql?('GLOBAL')
      end

      def reset_secret?(secret)
        return false if secret.nil? || !secret.exists? || secret.key.to_s.empty?

        Rack::Utils.secure_compare(reset_secret.to_s, secret.key)
      end

      def valid_reset_secret!(secret)
        if is_valid = reset_secret?(secret)
          OT.ld "[valid_reset_secret!] Reset secret is valid for #{custid} #{secret.shortkey}"
          secret.delete!
          reset_secret.delete!
        end
        is_valid
      end

      # Session management is now handled by Rack::Session middleware
      # This deprecated method has been removed as part of the migration
    end
  end
end
