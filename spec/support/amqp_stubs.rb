# spec/support/amqp_stubs.rb
#
# frozen_string_literal: true

# Shared AMQP stub classes for worker tests
#
# These Data classes mock AMQP envelope components used by Sneakers/Kicks workers.
# They provide immutable, minimal representations of delivery_info and metadata
# structures needed for testing worker message handling.
#
# Usage:
#   require 'spec/support/amqp_stubs'
#
#   let(:delivery_info) do
#     DeliveryInfoStub.new(
#       delivery_tag: 1,
#       routing_key: 'email.message.send',
#       redelivered?: false
#     )
#   end
#
#   let(:metadata) do
#     MetadataStub.new(
#       message_id: 'msg-12345-abcde',
#       headers: { 'x-schema-version' => 1 }
#     )
#   end

# Simulates Bunny::DeliveryInfo for testing worker message acknowledgment
DeliveryInfoStub = Data.define(:delivery_tag, :routing_key, :redelivered?) unless defined?(DeliveryInfoStub)

# Simulates Bunny::MessageProperties for testing message metadata extraction
MetadataStub = Data.define(:message_id, :headers) unless defined?(MetadataStub)
