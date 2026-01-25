# apps/api/account/logic/account/update_account_field.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Account
    # Abstract base class for updating specific account fields.
    #
    # Subclasses must implement the abstract methods marked with `raise NotImplemented`.
    # This pattern enforces a consistent interface for field update operations while
    # allowing each field type to define its own validation and update logic.
    #
    # @abstract Subclass and override the abstract methods to implement field updates.
    #
    # @example Implementing a concrete field updater
    #   class UpdateApiToken < UpdateAccountField
    #     def field_name = :apitoken
    #     def process_params = # parse and validate params
    #     def field_specific_concerns = # add validation errors
    #     def valid_update? = # return true if update should proceed
    #     def perform_update = # execute the update
    #     def success_data = # return response hash
    #   end
    #
    class UpdateAccountField < AccountAPI::Logic::Base
      attr_reader :modified, :greenlighted

      def initialize(*args)
        super
        @modified     = []
        @greenlighted = false
      end

      # @abstract Subclasses must implement to parse and validate request params.
      def process_params
        raise NotImplemented
      end

      def raise_concerns
        field_specific_concerns
      end

      def process
        return unless valid_update?

        @greenlighted = true
        log_update
        # TODO: Run in the database transaction
        perform_update
        @modified << field_name

        success_data
      end

      def modified?(field_name)
        modified.include?(field_name)
      end

      # @abstract Subclasses must implement to return the response data hash.
      def success_data
        raise NotImplemented
      end

      private

      # @abstract Subclasses must implement to return the field identifier (Symbol).
      def field_name
        raise NotImplemented
      end

      # @abstract Subclasses must implement to add field-specific validation errors.
      def field_specific_concerns
        raise NotImplemented
      end

      # @abstract Subclasses must implement to determine if the update should proceed.
      # @return [Boolean]
      def valid_update?
        raise NotImplemented
      end

      # @abstract Subclasses must implement to execute the actual update operation.
      def perform_update
        raise NotImplemented
      end

      def log_update
        OT.info "[update-account] #{field_name.to_s.capitalize} updated cid/#{cust.objid} r/#{cust.role}"
      end
    end
  end
end
