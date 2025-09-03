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

          # Use Familia 2's generated class methods
          def add(cust)
            values.add OT.now.to_i, cust.identifier
          end

          def all
            values.revrangeraw(0, -1).collect { |identifier| load(identifier) }
          end

          def recent(duration = 30.days, epoint = OT.now.to_i)
            spoint = OT.now.to_i - duration
            values.rangebyscoreraw(spoint, epoint).collect { |identifier| load(identifier) }
          end

          # This is where the global word that got really confusing in familia
          # for a while, trying to differentiate between places that used the
          # word global to mean class-level. It only exists here for historical
          # reasons. There's a key customer:GLOBAL:object that has the increment
          # fields in it (that's how we count the all time number of secrets
          # created, burned etc)
          def global
            @global ||= from_identifier(:GLOBAL) || create(:GLOBAL)
            @global
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
