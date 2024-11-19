# frozen_string_literal: true

require 'json'

module Onetime::Models

  # Module containing helper methods for session-related functionality
  module SessionMessages

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
      base.list :messages, ttl: 20.minutes
    end

    def set_form_fields hsh
      self.form_fields! hsh.to_json unless hsh.nil?
    end

    def get_form_fields!
      fields_json = self.form_fields
      return if fields_json.to_s.empty?
      ret = OT::Utils.indifferent_params JSON.parse(fields_json) # TODO: Use refinement
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
