# apps/web/billing/operations/process_webhook_event.rb
#
# frozen_string_literal: true

# Load all handlers
Dir[File.join(__dir__, 'webhook_handlers', '*.rb')].each { |f| require f }

#
# Processes Stripe webhook events by dispatching to type-specific handlers.
# Extracted from Webhooks controller for reuse in CLI replay and testing.
#
# Uses Strategy pattern with auto-discovered handlers that implement:
# - .handles?(event_type) - returns true for handled event types
# - #call - processes the event and returns a result symbol
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
#   # Handler is auto-discovered, no changes needed here
#
module Billing
  module Operations
    class ProcessWebhookEvent
      include Onetime::LoggerMethods

      # Memoized registry of all handler classes
      #
      # @return [Array<Class>] Handler classes that respond to .handles?
      def self.handler_registry
        @handler_registry ||= build_handler_registry
      end

      # Reset handler registry (useful for testing)
      def self.reset_handler_registry!
        @handler_registry = nil
      end

      # @param event [Stripe::Event] The Stripe webhook event to process
      # @param context [Hash] Optional context (e.g., { replay: true, skip_notifications: true })
      def initialize(event:, context: {})
        @event = event
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

      class << self
        private

        def build_handler_registry
          WebhookHandlers.constants
            .map { |const_name| WebhookHandlers.const_get(const_name) }
            .select { |klass| handler_class?(klass) }
        end

        def handler_class?(klass)
          klass.is_a?(Class) &&
            klass.respond_to?(:handles?) &&
            # Exclude abstract base classes by checking if they implement `process` directly.
            # Concrete handlers must override `process` from BaseHandler.
            klass.instance_method(:process).owner != WebhookHandlers::BaseHandler
        end
      end
    end
  end
end
