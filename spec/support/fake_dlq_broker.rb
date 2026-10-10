# spec/support/fake_dlq_broker.rb
#
# frozen_string_literal: true

require 'bunny'
require 'json'

# A stateful stand-in for one RabbitMQ classic queue and the channels that
# consume it, for the DLQ op specs (#4343). Unlike scripted pop stubs
# (store_peek_spec.rb), it keeps the state that decides whether a scan works:
#
# - A popped manual-ack delivery is out of the queue until it is acked,
#   nacked, or its channel closes.
# - A nack-requeued or channel-close-returned delivery goes back to its
#   ORIGINAL position, which is the head when it was popped from the head.
#   That is RabbitMQ's documented rule for a classic queue when no other
#   consumer took messages in between, and it is enough to expose the #4650
#   bug: a scan that requeues each non-match at once pops the head again.
# - In transaction mode (tx_select) publishes, acks and nacks wait for
#   tx_commit; tx_rollback discards them; closing the channel discards an
#   uncommitted transaction and returns every unacked delivery.
#
# Every broker-visible step is appended to `broker.events`, and the specs
# can append their own (an audit write) to check ordering across the two.
#
# The live-broker counterpart is spec/integration/all/jobs/dlq_message_ops_spec.rb.
module DlqFakeBroker
  Delivery   = Struct.new(:delivery_tag)
  Properties = Struct.new(:message_id, :headers, :content_type, :timestamp, keyword_init: true)

  # One message as published. `seq` is its position at enqueue time.
  Entry = Struct.new(:seq, :id, :headers, :content_type, :payload)

  module_function

  # @param ids [Array<String, nil>]
  # @param original_queue [String, nil] nil for a message without x-death
  def broker(ids, original_queue: 'billing.event.process', declared: true)
    Broker.new(ids.map { |id| message(id, original_queue: original_queue) }, declared: declared)
  end

  def message(id, original_queue: 'billing.event.process', payload: nil)
    headers = original_queue ? { 'x-death' => [{ 'queue' => original_queue, 'reason' => 'rejected', 'count' => 1 }] } : {}
    { id: id, headers: headers, content_type: 'application/json', payload: payload || JSON.generate(id: id) }
  end

  class Broker
    attr_reader :events, :published, :channels

    def initialize(messages, declared: true)
      @ready     = messages.each_with_index.map do |m, seq|
        Entry.new(seq, m[:id], m[:headers], m[:content_type], m[:payload])
      end
      @declared  = declared
      @events    = []
      @published = []
      @channels  = []
    end

    def declared? = @declared

    def ready_ids = @ready.map(&:id)

    def message_count = @ready.size

    def take
      @ready.shift
    end

    # Back to the original position, by enqueue order.
    def requeue(entry)
      index = @ready.index { |other| other.seq > entry.seq } || @ready.size
      @ready.insert(index, entry)
    end

    def connection = Connection.new(self)
  end

  class Connection
    def initialize(broker)
      @broker = broker
    end

    def create_channel
      Channel.new(@broker).tap { |ch| @broker.channels << ch }
    end
  end

  class Exchange
    def initialize(channel)
      @channel = channel
    end

    def publish(payload, **opts)
      @channel.transactional do
        @channel.broker.published << { payload: payload, opts: opts }
        @channel.broker.events << [:published, opts[:message_id], opts[:routing_key]]
      end
    end
  end

  class QueueHandle
    def initialize(channel)
      @channel = channel
    end

    def message_count = @channel.broker.message_count

    def pop(manual_ack:)
      raise 'DLQ ops must not auto-ack' unless manual_ack

      @channel.deliver
    end
  end

  class Channel
    attr_reader :broker, :unacked

    def initialize(broker)
      @broker   = broker
      @unacked  = {}
      @next_tag = 0
      @open     = true
      @pending  = nil
    end

    def queue(_name, durable:, passive:)
      raise 'DLQ ops must open a passive durable queue' unless durable && passive
      raise Bunny::NotFound.new('NOT_FOUND - no queue', self, nil) unless broker.declared?

      QueueHandle.new(self)
    end

    def deliver
      entry = broker.take
      return [nil, nil, nil] unless entry

      tag           = @next_tag += 1
      unacked[tag]  = entry
      broker.events << [:pop, entry.id]
      properties    = Properties.new(message_id: entry.id, headers: entry.headers,
        content_type: entry.content_type, timestamp: nil)
      [Delivery.new(tag), properties, entry.payload]
    end

    def default_exchange = (@default_exchange ||= Exchange.new(self))

    def transactional(&op)
      @pending ? @pending << op : op.call
    end

    def tx_select
      broker.events << [:tx_select]
      @pending ||= []
    end

    def tx_commit
      applied  = @pending || []
      @pending = []
      applied.each(&:call)
      broker.events << [:tx_commit]
    end

    def tx_rollback
      @pending = []
      broker.events << [:tx_rollback]
    end

    def ack(tag)
      transactional do
        entry = unacked.delete(tag) { raise 'unknown delivery tag' }
        broker.events << [:ack, entry.id]
      end
    end

    def nack(tag, multiple, requeue)
      raise 'DLQ ops settle one delivery at a time' if multiple

      transactional do
        entry = unacked.delete(tag) { raise 'unknown delivery tag' }
        broker.events << [(requeue ? :nack : :drop), entry.id]
        broker.requeue(entry) if requeue
      end
    end

    def open? = @open

    def close
      @pending = nil
      unacked.keys.sort.each { |tag| broker.requeue(unacked.delete(tag)) }
      @open = false
      broker.events << [:close]
    end
  end
end
