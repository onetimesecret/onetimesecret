# apps/api/v2/models/customer/features/customer_deprecated_fields.rb

module V2
  module Models
    module Features
      module CustomerDeprecatedFields
        def self.included(base)
          OT.ld "[#{name}] Included in #{base}"
          base.extend ClassMethods
          base.include InstanceMethods

          base.field :sessid
          base.field :apitoken # TODO: use sorted set?
          base.field :contributor
        end

        module ClassMethods
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

          # Loads an existing session or creates a new one if it doesn't exist.
          #
          # @param [String] ip_address The IP address of the customer.
          # @raise [Onetime::Problem] if the customer is anonymous.
          # @return [V2::Session] The loaded or newly created session.
          def load_or_create_session(ip_address)
            raise Onetime::Problem, 'Customer is anonymous' if anonymous?

            @sess = V2::Session.load(sessid) unless sessid.to_s.empty?
            if @sess.nil?
              @sess  = V2::Session.create(ip_address, custid)
              sessid = @sess.identifier
              OT.info "[load_or_create_session] adding sess #{sessid} to #{obscure_email}"
              sessid!(sessid)
            end
            @sess
          end
        end

        Familia::Base.add_feature self, :customer_deprecated_fields
      end
    end
  end
end
