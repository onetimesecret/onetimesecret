# spec/integration/rabbitmq_publishing_spec.rb

require 'onetime/jobs/publisher'

RSpec.describe 'RabbitMQ publishing', :rabbitmq do
  before(:all) do
    # Ensure clean state - no queues exist
    conn = Bunny.new('amqp://localhost')
    conn.start
    ch = conn.create_channel

    Onetime::Jobs::QueueConfig::QUEUES.keys.each do |queue_name|
      ch.queue_delete(queue_name) rescue nil
    end

    conn.close
  end

  it 'publishes successfully even when queue does not exist yet' do
    # Backend publishes to default exchange with routing key
    # Message waits in RabbitMQ until consumer declares queue and binds

    expect {
      Onetime::Jobs::Publisher.enqueue_email(:test, { to: 'test@example.com' })
    }.not_to raise_error
  end
end
