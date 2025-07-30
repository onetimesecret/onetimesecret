# apps/api/v2/logic/account/update_account_field.rb

module V2::Logic
  module Account
    # Base class for updating specific account fields
    class UpdateAccountField < V2::Logic::Base
      attr_reader :modified, :greenlighted

      def initialize(*args)
        super
        @modified = []
        @greenlighted = false
      end

      def process_params
        raise NotImplemented
      end

      def raise_concerns

        field_specific_concerns
      end

      def process
        if valid_update?
          @greenlighted = true
          log_update
          # TODO: Run in redis transaction
          perform_update
          @modified << field_name
        end
      end

      def modified?(field_name)
        modified.include?(field_name)
      end

      def success_data
        raise NotImplemented
      end

      private

      def field_name
        raise NotImplemented
      end

      def field_specific_concerns
        raise NotImplemented
      end

      def valid_update?
        raise NotImplemented
      end

      def perform_update
        raise NotImplemented
      end

      def log_update
        OT.info "[update-account] #{field_name.to_s.capitalize} updated cid/#{cust.custid} r/#{cust.role} ipa/#{sess.ipaddress}"
      end
    end
  end
end
