# apps/api/v2/models/mixins/session_messages.rb

require 'json'
require 'onetime/refinements/hash_refinements'

module V2
  module Mixins

    # Provides session-based messaging and form state persistence functionality
    #
    # @example Basic usage
    #   class MyModel
    #     include SessionMessages
    #
    #     def process_form
    #       set_error_message("Invalid input")
    #       set_form_fields(params)
    #     end
    #   end
    #
    # Key Features:
    # - Temporary form field storage for error recovery
    # - Flash-style messaging between requests
    # - Support for error and info message types
    # - Auto-expiring messages via Redis TTL
    #
    # Implementation Notes:
    # - form_fields remains server-side only, not exposed to frontend
    # - messages rendered via session_messages.html template and window state
    #   as `messages` array of objects.
    # - 20 minute TTL on message persistence
    module SessionMessages

      using IndifferentHashAccess

      def self.included base
        # In some UI flows, we temporarily store form values after a form
        # error so that the form UI inputs can be prepopulated, even if
        # there's a redirect in between. Ideally we can move this to local
        # storage with Vue.
        base.field :form_fields

        # Used to pass UI-facing feedback between requests. Typically this
        # be empty almost all of the time and when populated, only very
        # briefly between requests. In theory it could also be used for
        # displaying a message to a user the next time they load a page.
        #
        # Each message is a small JSON blob: {type: 'error', content: '...'}
        #
        # We give them a very short shelf life so they don't linger
        # around and confuse the user.
        base.list :messages, ttl: 15.seconds
      end

      def set_form_fields hsh
        self.form_fields! hsh.to_json unless hsh.nil?
      end

      def get_form_fields!
        fields_json = self.form_fields
        return if fields_json.to_s.empty?
        ret = JSON.parse(fields_json)
        self.remove :form_fields
        ret
      rescue JSON::ParserError => ex
        OT.le "Error parsing JSON fields: #{ex.message}"
        nil
      end

      def set_error_message msg
        self.messages << _json(msg, :error)
      end

      def set_info_message msg
        self.messages << _json(msg, :info)
      end

      def set_success_message msg
        self.messages << _json(msg, :success)
      end

      def get_messages
        messages.to_a.filter_map do |message|
          next if message.to_s.empty?
          JSON.parse(message, symbolize_names: true)
        rescue JSON::ParserError => e
          OT.le "Error parsing JSON message: #{e.message}"
          nil
        end
      end

      def get_info_messages
        messages.to_a.filter_map do |message|
          next if message.to_s.empty?

          detail = JSON.parse(message, symbolize_names: true)
          detail if detail[:type].eql?('info')
        rescue JSON::ParserError => e
          OT.le "Error parsing JSON message: #{e.message}"
          nil
        end
      end

      def get_error_messages
        messages.to_a.filter_map do |message|
          next if message.to_s.empty?

          detail = JSON.parse(message, symbolize_names: true)
          detail if detail[:type].eql?('error')
        rescue JSON::ParserError => ex
          OT.le "Error parsing JSON error message: #{ex.message}"
          nil
        end
      end

      def clear_messages!
        self.messages.clear
      end

      def _json msg, type=:error
        {type: type, content: msg}.to_json
      end
      private :_json

    end
  end

end
