# lib/onetime/jobs/workers/envelope.rb
#
# frozen_string_literal: true

require_relative '../trace_propagation'
require_relative '../queues/config'

module Onetime
  module Jobs
    module Workers
      # The AMQP envelope of one message: the delivery info and the message
      # properties RabbitMQ hands to work_with_params, and the facts workers
      # read from them.
      #
      # A worker builds one at the top of work_with_params and passes it to
      # every helper that needs it. Kicks runs work_with_params on a thread
      # pool against ONE worker instance, so per-message state is a local
      # passed down the call chain, never an instance variable.
      #
      # The value is frozen and every reader is nil-safe: an envelope built
      # from a nil delivery_info or nil metadata answers nil (or an empty
      # hash for trace headers) instead of raising.
      #
      # Example:
      #   envelope = Envelope.new(delivery_info, metadata)
      #   envelope.message_id   #=> "5f0c..."
      #   envelope.redelivered? #=> false
      #
      class Envelope
        # Schema version of a message published without the header.
        DEFAULT_SCHEMA_VERSION = 1

        attr_reader :delivery_info, :metadata

        # @param delivery_info [Bunny::DeliveryInfo, nil] AMQP delivery info
        # @param metadata [Bunny::MessageProperties, nil] AMQP message properties
        def initialize(delivery_info = nil, metadata = nil)
          @delivery_info = delivery_info
          @metadata      = metadata
          freeze
        end

        # @return [String, nil] the AMQP message_id property
        def message_id
          metadata&.message_id
        end

        # @return [Integer, nil] the broker's delivery tag
        def delivery_tag
          delivery_info&.delivery_tag
        end

        # @return [String, nil] the routing key the message was published with
        def routing_key
          delivery_info&.routing_key
        end

        # Whether the broker has delivered this message before.
        #
        # Useful for logging and for bounding requeues, but not a substitute
        # for the idempotency claim. A message can be delivered exactly once
        # and still be a duplicate (publisher retry before broker ack), and a
        # redelivered message might legitimately need processing (the worker
        # crashed before its code ran). The Valkey claim remains the source
        # of truth.
        #
        # @return [Boolean, nil] nil when there is no delivery info
        def redelivered?
          delivery_info&.redelivered?
        end

        # @return [Hash, nil] the AMQP headers, or nil when there are none
        def headers
          value = metadata&.headers
          value.is_a?(Hash) ? value : nil
        end

        # @return [Object, nil] the x-schema-version header as published, or
        #   nil when the message carries none
        def schema_version_header
          headers&.[]('x-schema-version')
        end

        # @return [Object] the schema version the message is read as: the
        #   header, or DEFAULT_SCHEMA_VERSION when the header is missing
        def schema_version
          schema_version_header || DEFAULT_SCHEMA_VERSION
        end

        # @return [Boolean] whether this build understands the schema version
        def schema_version_known?
          Onetime::Jobs::QueueConfig::Versions.const_defined?("V#{schema_version}")
        rescue NameError
          # A header that does not form a constant name is an unknown version
          false
        end

        # Sentry trace headers carried by the message. Empty for a message
        # published without them.
        #
        # @return [Hash<String, String>]
        def trace_headers
          Onetime::Jobs::TracePropagation.parse_trace_headers(metadata)
        end

        # The envelope fields workers put in log lines.
        #
        # @return [Hash]
        def summary
          {
            delivery_tag: delivery_tag,
            routing_key: routing_key,
            redelivered: redelivered?,
            message_id: message_id,
            schema_version: schema_version_header,
          }
        end

        # Bunny's delivery info holds the channel and consumer; keep them out
        # of inspect output.
        def inspect
          "#<#{self.class.name} #{summary}>"
        end
        alias to_s inspect
      end
    end
  end
end
