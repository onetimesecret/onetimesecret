# apps/api/v2/controllers/class_settings.rb

module V2
  # ControllerSettings module provides configuration options for UTF-8 and URI
  # encoding middleware checks.
  #
  # This module is designed to be included in V2 controller subclasses.
  #
  module Controllers
    module ClassSettings
      # Default settings for UTF-8 and URI encoding checks
      @check_utf8         = nil
      @check_uri_encoding = nil

      # When this module is included in a class, it extends that class
      # with ClassMethods and sets up the initial configuration
      #
      # @param base [Class] The class including this module
      def self.included(base)
        base.instance_variable_set(:@check_utf8, @check_utf8)
        base.instance_variable_set(:@check_uri_encoding, @check_uri_encoding)
        base.extend(ClassMethods)
      end

      # ClassMethods module provides class-level accessor methods
      # for configuring UTF-8 and URI encoding checks
      module ClassMethods
        # @!attribute [rw] check_utf8
        #   @return [Boolean] Whether to check for valid UTF-8 encoding
        def check_utf8
          @check_utf8
        end

        def check_utf8=(value)
          @check_utf8 = value
        end

        # @!attribute [rw] check_uri_encoding
        #   @return [Boolean] Whether to check for valid URI encoding
        def check_uri_encoding
          @check_uri_encoding
        end

        def check_uri_encoding=(value)
          @check_uri_encoding = value
        end
      end
    end
  end
end
