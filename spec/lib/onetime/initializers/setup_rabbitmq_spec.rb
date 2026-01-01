# spec/lib/onetime/initializers/setup_rabbitmq_spec.rb

RSpec.describe Onetime::Initializers::SetupRabbitMQ do
  let(:initializer) { described_class.new }
  let(:mock_channel) { instance_double(Bunny::Channel) }
  let(:mock_connection) { instance_double(Bunny::Session, start: true, create_channel: mock_channel, open?: true) }
  let(:mock_pool) { instance_double(ConnectionPool) }

  let(:test_config) do
    {
      'jobs' => {
        'enabled' => true,
        'rabbitmq_url' => 'amqp://localhost',
        'channel_pool_size' => 5
      }
    }
  end

  before do
    allow(OT).to receive(:conf).and_return(test_config)
    allow(Bunny).to receive(:new).and_return(mock_connection)
    allow(ConnectionPool).to receive(:new).and_return(mock_pool)
    allow(mock_pool).to receive(:with).and_yield(mock_channel)
  end

  describe '#execute' do
    it 'declares dead letter infrastructure' do
      # DLX exchanges
      allow(mock_channel).to receive(:fanout)
      expect(mock_channel).to receive(:fanout).with('dlx.email.message', durable: true)
      expect(mock_channel).to receive(:fanout).with('dlx.notifications.alert', durable: true)
      # ... etc

      # DLQ queues
      dlq = instance_double(Bunny::Queue)
      allow(mock_channel).to receive(:queue).with(/^dlq\./, any_args).and_return(dlq)
      allow(dlq).to receive(:bind)

      initializer.execute(nil)
    end

    it 'does not declare work queues (workers own that)' do
      # Allow DLX setup
      allow(mock_channel).to receive(:fanout)
      dlq = instance_double(Bunny::Queue, bind: true)
      allow(mock_channel).to receive(:queue).with(/^dlq\./, any_args).and_return(dlq)

      # Fail if work queues are declared
      expect(mock_channel).not_to receive(:queue).with('email.message.send', anything)
      expect(mock_channel).not_to receive(:queue).with('notifications.alert.push', anything)
      expect(mock_channel).not_to receive(:queue).with('billing.event.process', anything)

      initializer.execute(nil)
    end
  end
end

RSpec.describe Onetime::Initializers::SetupRabbitMQ, :rabbitmq do
  before(:all) do
    # Reset RabbitMQ
    conn = Bunny.new('amqp://localhost')
    conn.start
    ch = conn.create_channel

    # Delete everything
    %w[dlq.email.message email.message.send].each do |q|
      ch.queue_delete(q) rescue nil
    end
    %w[dlx.email.message].each do |x|
      ch.exchange_delete(x) rescue nil
    end

    conn.close
  end

  it 'declares DLX infrastructure but not work queues' do
    # Force enable jobs
    allow(OT).to receive(:conf).and_return({
      'jobs' => {
        'enabled' => true,
        'rabbitmq_url' => 'amqp://localhost',
        'channel_pool_size' => 1
      }
    })

    # Run the initializer
    described_class.new.execute(nil)

    # Check what exists
    conn = Bunny.new('amqp://localhost')
    conn.start
    ch = conn.create_channel

    # DLQ should exist
    expect { ch.queue('dlq.email.message', passive: true) }.not_to raise_error

    # Work queue should NOT exist (Sneakers owns it)
    expect { ch.queue('email.message.send', passive: true) }.to raise_error(Bunny::NotFound)

    conn.close
  end
end
