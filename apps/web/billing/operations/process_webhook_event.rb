# apps/web/billing/operations/process_webhook_event.rb
#
# frozen_string_literal: true

#
# Processes Stripe webhook events by dispatching to type-specific handlers.
# Extracted from Webhooks controller for reuse in CLI replay and testing.
#
# Uses Strategy pattern with self-registering handlers that implement:
# - .handles?(event_type) - returns true for handled event types
# - #call - processes the event and returns a result symbol
#
# Handlers auto-register via BaseHandler.inherited when their files are loaded.
# Abstract base classes call `abstract_handler!` to exclude themselves.
#
# @example Adding a new handler
#   # Create apps/web/billing/operations/webhook_handlers/invoice_paid.rb
#   class InvoicePaid < BaseHandler
#     def self.handles?(event_type)
#       event_type == 'invoice.paid'
#     end
#
#     protected
#
#     def process
#       # Handler logic
#       :success
#     end
#   end
#   # Handler auto-registers via inherited callback, no changes needed here
#
module Billing
  module Operations
    class ProcessWebhookEvent
      include Onetime::LoggerMethods

      @handler_registry = []

      # Register a handler class
      #
      # @param handler_class [Class] Handler class that responds to .handles?
      def self.register(handler_class)
        @handler_registry << handler_class unless @handler_registry.include?(handler_class)
      end

      # Get registered handler classes
      #
      # @return [Array<Class>] Handler classes that respond to .handles?
      class << self
        attr_reader :handler_registry
      end

      # Reset handler registry (useful for testing)
      def self.reset_handler_registry!
        @handler_registry = []
      end

      # @param event [Stripe::Event] The Stripe webhook event to process
      # @param context [Hash] Optional context (e.g., { replay: true, skip_notifications: true })
      def initialize(event:, context: {})
        @event   = event
        @context = context
      end

      # Executes the webhook event processing
      #
      # Dispatches to appropriate handler based on event type.
      # Raises exceptions on failure so callers can handle rollback.
      #
      # @return [Symbol] Result of processing:
      #   - :success - Event processed successfully
      #   - :skipped - Event intentionally skipped
      #   - :not_found - Required entity not found
      #   - :unhandled - No handler for this event type
      # @raise [StandardError] If event processing fails
      def call
        handler_class = find_handler

        if handler_class
          handler_class.new(event: @event, context: @context).call
        else
          billing_logger.debug 'Unhandled webhook event type', {
            event_type: @event.type,
          }
          :unhandled
        end
      end

      private

      def find_handler
        self.class.handler_registry.find { |h| h.handles?(@event.type) }
      end
    end
  end
end

# Load all handlers (after ProcessWebhookEvent is defined so they can register)
Dir[File.join(__dir__, 'webhook_handlers', '*.rb')].each { |f| require f }
