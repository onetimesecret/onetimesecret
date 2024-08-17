# frozen_string_literal: true

module Onetime::Models

  # Module containing helper methods for session-related functionality
  module SessionMessages

    def self.included base
      # In some UI flows, we temporarily store form values after a form
      # error so that the form UI inputs can be prepopulated, even if
      # there's a redirect inbetween. Ideally we can move this to local
      # storage with Vue.
      base.field :form_fields

      # Used to pass UI-facing feedback between requests. Typically this
      # be empty almost all of the time and when populated, only very
      # briefly between requests. In theory it could also be used for
      # displaying a message to a user the next time they load a page.
      #
      # Each message is a small JSON blob: {type: 'error', content: '...'}
      base.list :messages
    end


    def set_form_fields hsh
      self.form_fields = hsh.to_json unless hsh.nil?
    end

    def get_form_fields!
      fields_json = self.form_fields # previously name self.form_fields!
      return if fields_json.nil?
      self.form_fields = nil
      OT::Utils.indifferent_params Yajl::Parser.parse(fields_json)
    end

    def unset_error_message
      self.error_message = nil # todo
    end

    def set_error_message msg
      self.error_message = msg
    end

    def set_info_message msg
      self.info_message = msg
    end

    def session_group groups
      sessid.to_i(16) % groups.to_i
    end

  end
end
