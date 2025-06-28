# tests/unit/ruby/rspec/onetime/classmethods_spec.rb

require_relative '../spec_helper'

RSpec.describe Onetime::ClassMethods do
  let(:test_class) do
    Class.new do
      extend Onetime::ClassMethods
    end
  end

  before do
    @original_env = ENV.to_hash
  end

  after do
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
    # Reset memoized values
    test_class.instance_variable_set(:@debug, nil)
    test_class.instance_variable_set(:@env, nil)
  end

  describe 'timestamp methods' do
    describe '#hnowµs' do
      it 'returns an integer representing microseconds' do
        result = test_class.hnowµs
        expect(result).to be_an(Integer)
        expect(result).to be > 1_600_000_000_000_000 # roughly 2020
      end

      it 'returns different values when called sequentially' do
        first = test_class.hnowµs
        sleep(0.001) # 1ms
        second = test_class.hnowµs
        expect(second).to be > first
      end
    end

    describe '#nowµs' do
      it 'returns an integer representing microseconds' do
        result = test_class.nowµs
        expect(result).to be_an(Integer)
        expect(result).to be > 1_600_000_000_000_000 # roughly 2020
      end

      it 'returns different values when called sequentially' do
        first = test_class.nowµs
        sleep(0.001) # 1ms
        second = test_class.nowµs
        expect(second).to be > first
      end
    end

    describe '#now' do
      it 'returns a Time object in UTC' do
        result = test_class.now
        expect(result).to be_a(Time)
        expect(result.zone).to eq('UTC')
      end

      it 'returns current time' do
        before_time = Time.now.utc
        result = test_class.now
        after_time = Time.now.utc
        expect(result).to be_between(before_time, after_time)
      end
    end

    describe '#hnow' do
      it 'returns a Float representing seconds' do
        result = test_class.hnow
        expect(result).to be_a(Float)
        expect(result).to be > 1_600_000_000 # roughly 2020
      end

      it 'has sub-second precision' do
        first = test_class.hnow
        sleep(0.001) # 1ms
        second = test_class.hnow
        expect(second - first).to be > 0.0005 # at least 0.5ms difference
      end
    end
  end

  describe '#mode?' do
    it 'returns false when mode is not set' do
      expect(test_class.mode?(:app)).to be false
    end

    it 'compares mode as strings when set' do
      test_class.instance_variable_set(:@mode, :app)
      expect(test_class.mode?(:app)).to be true
      expect(test_class.mode?('app')).to be true
      expect(test_class.mode?(:cli)).to be false
    end

    it 'handles nil mode' do
      test_class.instance_variable_set(:@mode, nil)
      expect(test_class.mode?(nil)).to be true
      expect(test_class.mode?('')).to be true
    end
  end

  describe 'logging methods' do
    before do
      allow(test_class).to receive(:stdout)
      allow(test_class).to receive(:stderr)
    end

    describe '#info' do
      it 'outputs info messages when mode is app' do
        test_class.instance_variable_set(:@mode, :app)
        expect(test_class).to receive(:stdout).with('I', 'test message')
        test_class.info('test message')
      end

      it 'outputs info messages when mode is cli' do
        test_class.instance_variable_set(:@mode, :cli)
        expect(test_class).to receive(:stdout).with('I', 'test message')
        test_class.info('test message')
      end

      it 'does not output when mode is not app or cli' do
        test_class.instance_variable_set(:@mode, :tryout)
        expect(test_class).not_to receive(:stdout)
        test_class.info('test message')
      end

      it 'joins multiple messages' do
        test_class.instance_variable_set(:@mode, :app)
        expect(test_class).to receive(:stdout).with('I', "msg1#{$/}msg2")
        test_class.info('msg1', 'msg2')
      end
    end

    describe '#li' do
      it 'always outputs info messages' do
        expect(test_class).to receive(:stdout).with('I', 'test message')
        test_class.li('test message')
      end
    end

    describe '#lw' do
      it 'outputs warning messages' do
        expect(test_class).to receive(:stdout).with('W', 'warning message')
        test_class.lw('warning message')
      end
    end

    describe '#le' do
      it 'outputs error messages' do
        expect(test_class).to receive(:stderr).with('E', 'error message')
        test_class.le('error message')
      end
    end

    describe '#ld' do
      it 'outputs debug messages when debug is enabled' do
        allow(Onetime).to receive(:debug).and_return(true)
        expect(test_class).to receive(:stderr).with('D', 'debug message')
        test_class.ld('debug message')
      end

      it 'does not output debug messages when debug is disabled' do
        allow(Onetime).to receive(:debug).and_return(false)
        expect(test_class).not_to receive(:stderr)
        test_class.ld('debug message')
      end
    end
  end

  describe 'output methods' do
    let(:timestamp) { 1_234_567_890 }

    before do
      allow(Time).to receive_message_chain(:now, :to_i).and_return(timestamp)
    end

    describe '#stdout' do
      it 'outputs formatted message when STDOUT is open' do
        expect(STDOUT).to receive(:puts).with('I(1234567890): test message')
        test_class.stdout('I', 'test message')
      end

      it 'does not output when STDOUT is closed' do
        allow(STDOUT).to receive(:closed?).and_return(true)
        expect(STDOUT).not_to receive(:puts)
        test_class.stdout('I', 'test message')
      end
    end

    describe '#stderr' do
      it 'outputs formatted message when STDERR is open' do
        expect(test_class).to receive(:warn).with('E(1234567890): error message')
        test_class.stderr('E', 'error message')
      end

      it 'does not output when STDERR is closed' do
        allow(STDERR).to receive(:closed?).and_return(true)
        expect(STDERR).not_to receive(:puts)
        test_class.stderr('E', 'error message')
      end
    end
  end

  describe '#with_diagnostics' do
    let(:mock_config) { { enabled: true } }

    it 'executes block when diagnostics are enabled' do
      allow(Onetime).to receive(:conf).and_return({ diagnostics: mock_config })
      executed = false
      test_class.with_diagnostics { executed = true }
      expect(executed).to be true
    end

    it 'does not execute block when diagnostics are disabled' do
      allow(Onetime).to receive(:conf).and_return({ diagnostics: { enabled: false } })
      executed = false
      test_class.with_diagnostics { executed = true }
      expect(executed).to be false
    end

    it 'does not execute block when diagnostics config is missing' do
      allow(Onetime).to receive(:conf).and_return({})
      executed = false
      test_class.with_diagnostics { executed = true }
      expect(executed).to be false
    end
  end
end
