require_relative '../../app_helpers'
require_relative '../../../../altcha'

module Onetime::App
  class APIV2
    module Base
      include Onetime::App::API::Base

      def publically
        carefully do
          check_locale!
          yield
        end
      end

      def colonels
        authorized do
          raise OT::Unauthorized, "No such customer" unless cust.role?(:colonel)
          yield
        end
      end

      # Retrieves and lists records of the specified class. Also used for single
      # records. It's up to the logic class what it wants to return via
      # `logic.success_data`` (i.e. `record: {...}` or `records: [...]`` ).
      #
      # @param logic_class [Class] The logic class for processing the request.
      # @param auth_type [Symbol] The authorization type to use (:authorized or :colonels).
      #
      # @return [void]
      #
      # @example
      #   retrieve_records(UserLogic)
      #   retrieve_records(SecretDocumentLogic, auth_type: :colonels)
      #
      def retrieve_records(logic_class, auth_type: :authorized)
        auth_method = auth_type == :colonels ? method(:colonels) : method(:authorized)

        auth_method.call do
          OT.ld "[retrieve] #{logic_class}"
          logic = logic_class.new(sess, cust, req.params, locale)
          logic.raise_concerns
          logic.process
          json success: true, **logic.success_data
        end
      end

      # Processes an action using the specified logic class and handles the response.
      #
      # @param logic_class [Class] The class implementing the action logic.
      # @param error_message [String] The error message to display if the action fails.
      #
      # The logic class must implement the following methods:
      # - raise_concerns
      # - process_params
      # - process
      # - greenlighted
      # - success_data
      #
      # @yield [logic] Gives access to the logic object for custom success handling.
      # @yieldparam logic [Object] The instantiated logic object after processing.
      #
      # @return [void]
      #
      # @example
      #   process_action(OT::Logic::GenerateAPIToken, "API Token could not be generated.") do |logic|
      #     json_success(custid: cust.custid, apitoken: logic.apitoken)
      #   end
      #
      def process_action(logic_class, success_message, error_message)
        authorized do
          logic = logic_class.new(sess, cust, req.params, locale)
          logic.raise_concerns
          logic.process
          OT.ld "[process_action] #{logic_class} success=#{logic.greenlighted}"
          if logic.greenlighted
            json_success(custid: cust.custid, **logic.success_data)
          else
            error_response(error_message)
          end
        end
      end

      def json hsh
        res.header['Content-Type'] = "application/json; charset=utf-8"
        res.body = hsh.to_json
      end

      # We don't get here from a form error unless the shrimp for this
      # request was good. Pass a delicious fresh shrimp to the client
      # so they can try again with a new one (without refreshing the
      # entire page).
      def handle_form_error ex, hsh={}
        hsh[:shrimp] = sess.add_shrimp
        error_response ex.message, hsh
      end

      def not_found_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end

      def error_response msg, hsh={}
        hsh[:message] = msg
        hsh[:success] = false
        res.status = 403 # Forbidden
        json hsh
      end

    end
  end
end
