# apps/web/billing/operations/webhook_handlers/base_handler.rb
#
# frozen_string_literal: true

module Billing
  module Operations
    module WebhookHandlers
      # Base class for Stripe webhook event handlers.
      #
      # Provides Template Method pattern with:
      # - Consistent logging (start, complete, error)
      # - Error handling with backtrace capture
      # - Context flags (replay?, skip_notifications?)
      # - Auto-registration with ProcessWebhookEvent via inherited callback
      #
      # Subclasses must implement:
      # - .handles?(event_type) - class method returning true for handled events
      # - #process - protected method containing handler logic
      #
      # Abstract intermediate base classes should call `abstract_handler!` to
      # exclude themselves from registration.
      #
      # @example Concrete handler
      #   class SubscriptionPaused < BaseHandler
      #     def self.handles?(event_type)
      #       event_type == 'customer.subscription.paused'
      #     end
      #
      #     protected
      #
      #     def process
      #       # Handler logic here
      #       :success
      #     end
      #   end
      #
      # @example Abstract intermediate base class
      #   class SubscriptionHandler < BaseHandler
      #     abstract_handler!  # Excludes from registration
      #
      #     # Shared logic for subscription handlers...
      #   end
      #
      class BaseHandler
        include Onetime::LoggerMethods

        @abstract = true # BaseHandler itself is abstract

        # Mark this handler class as abstract (not registered)
        def self.abstract_handler!
          @abstract = true
        end

        # Check if this handler class is abstract
        def self.abstract?
          @abstract == true
        end

        # Auto-register concrete handlers when they inherit from BaseHandler
        def self.inherited(subclass)
          super
          # Schedule registration after the class is fully defined
          # Use TracePoint to detect when class definition ends
          trace = TracePoint.new(:end) do |tp|
            if tp.self == subclass
              trace.disable
              # Only register non-abstract handlers
              unless subclass.abstract?
                Billing::Operations::ProcessWebhookEvent.register(subclass)
              end
            end
          end
          trace.enable
        end

        # @param event_type [String] Stripe event type
        # @return [Boolean] true if this handler processes the event type
        def self.handles?(event_type)
          raise NotImplementedError, "#{name} must implement .handles?"
        end

        # @param event [Stripe::Event] The Stripe webhook event
        # @param context [Hash] Optional context (e.g., { replay: true })
        def initialize(event:, context: {})
          @event       = event
          @data_object = event.data.object
          @context     = context
        end

        # Execute the handler with logging and error handling
        #
        # @return [Symbol] Result of processing (:success, :skipped, :not_found)
        # @raise [StandardError] Re-raises after logging
        def call
          log_start
          result = process
          log_complete(result)
          result
        rescue StandardError => ex
          log_error(ex)
          raise
        end

        protected

        # Subclasses implement this method with handler logic
        #
        # @return [Symbol] :success, :skipped, or :not_found
        def process
          raise NotImplementedError, "#{self.class.name} must implement #process"
        end

        # @return [Boolean] true if this is a replay of a historical event
        def replay?
          @context[:replay] == true
        end

        # @return [Boolean] true if notifications should be skipped
        def skip_notifications?
          @context[:skip_notifications] == true
        end

        private

        def log_start
          billing_logger.info "Processing #{@event.type}", {
            event_id: @event.id,
            replay: replay?,
          }
        end

        def log_complete(result)
          billing_logger.info "#{@event.type} completed", { result: result }
        end

        def log_error(error)
          billing_logger.error "#{@event.type} failed", {
            error: error.message,
            backtrace: error.backtrace&.first(5),
          }
        end
      end
    end
  end
end
