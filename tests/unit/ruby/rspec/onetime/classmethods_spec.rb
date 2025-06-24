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
  end

  describe '#env' do


    context 'without RACK_ENV set' do
      it 'defaults to production' do
        ENV.delete('RACK_ENV')
        expect(test_class.env).to eq('production')
      end
    end
  end

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

    it 'returns similar values to hnowµs' do
      hnow_result = test_class.hnowµs
      now_result = test_class.nowµs
      # Should be within a few milliseconds
      expect((hnow_result - now_result).abs).to be < 10_000
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

  describe '#debug and #debug?' do
    context 'when ONETIME_DEBUG is true' do
      it 'returns true for various true values' do
        %w[true TRUE 1].each do |value|
          ENV['ONETIME_DEBUG'] = value
          test_class.instance_variable_set(:@debug, nil) # reset memoization
          expect(test_class.debug).to be true
          expect(test_class.debug?).to be true
        end
      end
    end

    context 'when ONETIME_DEBUG is false or unset' do
      it 'returns false' do
        %w[false FALSE 0 random].each do |value|
          ENV['ONETIME_DEBUG'] = value
          test_class.instance_variable_set(:@debug, nil) # reset memoization
          expect(test_class.debug).to be false
          expect(test_class.debug?).to be false
        end
      end

      it 'returns false when unset' do
        ENV.delete('ONETIME_DEBUG')
        test_class.instance_variable_set(:@debug, nil) # reset memoization
        expect(test_class.debug).to be false
        expect(test_class.debug?).to be false
      end
    end
  end

  describe '#mode?' do
    it 'compares mode as strings' do
      allow(test_class).to receive(:mode).and_return(:app)
      expect(test_class.mode?(:app)).to be true
      expect(test_class.mode?('app')).to be true
      expect(test_class.mode?(:cli)).to be false
    end

    it 'handles nil mode' do
      allow(test_class).to receive(:mode).and_return(nil)
      expect(test_class.mode?(nil)).to be true
      expect(test_class.mode?('')).to be true
    end
  end

  describe 'environment convenience methods' do
    describe '#production?' do
      it 'returns true for production environments' do
        %w[prod production].each do |env|
          ENV['RACK_ENV'] = env
          expect(test_class.production?).to be true
        end
      end

      it 'returns false for non-production environments' do
        %w[dev development test staging].each do |env|
          ENV['RACK_ENV'] = env
          expect(test_class.production?).to be false
        end
      end

      it 'executes block when in production' do
        ENV['RACK_ENV'] = 'production'
        executed = false
        test_class.production? { executed = true }
        expect(executed).to be true
      end

      it 'does not execute block when not in production' do
        ENV['RACK_ENV'] = 'development'
        executed = false
        test_class.production? { executed = true }
        expect(executed).to be false
      end
    end

    describe '#development?' do
      it 'returns true for development environments' do
        %w[dev development].each do |env|
          ENV['RACK_ENV'] = env
          expect(test_class.development?).to be true
        end
      end

      it 'returns false for non-development environments' do
        %w[prod production test staging].each do |env|
          ENV['RACK_ENV'] = env
          expect(test_class.development?).to be false
        end
      end

      it 'executes block when in development' do
        ENV['RACK_ENV'] = 'development'
        executed = false
        test_class.development? { executed = true }
        expect(executed).to be true
      end
    end

    describe '#testing?' do
      it 'returns true for test environments' do
        %w[test testing].each do |env_value|
          ENV['RACK_ENV'] = env_value
          expect(test_class.testing?).to be true
        end
      end

      it 'returns false for non-test environments' do
        %w[dev development prod production staging].each do |env_value|
          ENV['RACK_ENV'] = env_value
          expect(test_class.testing?).to be false
        end
      end

      it 'executes block when in test' do
        ENV['RACK_ENV'] = 'test'
        executed = false
        test_class.testing? { executed = true }
        expect(executed).to be true
      end
    end

    describe '#staging?' do
      it 'returns true for staging environments' do
        %w[stage staging].each do |env|
          ENV['RACK_ENV'] = env
          expect(test_class.staging?).to be true
        end
      end

      it 'returns false for non-staging environments' do
        %w[dev development prod production test].each do |env|
          ENV['RACK_ENV'] = env
          expect(test_class.staging?).to be false
        end
      end

      it 'executes block when in staging' do
        ENV['RACK_ENV'] = 'staging'
        executed = false
        test_class.staging? { executed = true }
        expect(executed).to be true
      end
    end
  end

  describe '#env_matches?' do
    it 'returns true when environment matches any pattern' do
      ENV['RACK_ENV'] = 'development'
      expect(test_class.send(:env_matches?, %w[dev development])).to be true
    end

    it 'returns false when environment matches no patterns' do
      ENV['RACK_ENV'] = 'production'
      expect(test_class.send(:env_matches?, %w[dev development])).to be false
    end

    it 'executes block when match found' do
      ENV['RACK_ENV'] = 'production'
      executed = false
      test_class.send(:env_matches?, %w[production]) { executed = true }
      expect(executed).to be true
    end

    it 'does not execute block when no match' do
      ENV['RACK_ENV'] = 'development'
      executed = false
      test_class.send(:env_matches?, %w[production]) { executed = true }
      expect(executed).to be false
    end
  end

  describe 'logging methods' do
    before do
      allow(test_class).to receive(:stdout)
      allow(test_class).to receive(:stderr)
    end

    describe '#info' do
      context 'when mode is app or cli' do
        it 'outputs info messages' do
          allow(test_class).to receive(:mode).and_return(:app)
          expect(test_class).to receive(:stdout).with('I', 'test message')
          test_class.info('test message')
        end

        it 'joins multiple messages' do
          allow(test_class).to receive(:mode).and_return(:cli)
          expect(test_class).to receive(:stdout).with('I', "msg1#{$/}msg2")
          test_class.info('msg1', 'msg2')
        end
      end

      context 'when mode is not app or cli' do
        it 'does not output messages' do
          allow(test_class).to receive(:mode).and_return(:tryout)
          expect(test_class).not_to receive(:stdout)
          test_class.info('test message')
        end
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
      context 'when debug is enabled' do
        it 'outputs debug messages' do
          allow(Onetime).to receive(:debug).and_return(true)
          expect(test_class).to receive(:stderr).with('D', 'debug message')
          test_class.ld('debug message')
        end
      end

      context 'when debug is disabled' do
        it 'does not output debug messages' do
          allow(Onetime).to receive(:debug).and_return(false)
          expect(test_class).not_to receive(:stderr)
          test_class.ld('debug message')
        end
      end
    end
  end

  describe '#stdout and #stderr' do
    let(:timestamp) { 1_234_567_890 }

    before do
      allow(Time).to receive_message_chain(:now, :to_i).and_return(timestamp)
    end

    describe '#stdout' do
      context 'when STDOUT is open' do
        it 'outputs formatted message' do
          expect(STDOUT).to receive(:puts).with('I(1234567890): test message')
          test_class.stdout('I', 'test message')
        end
      end

      context 'when STDOUT is closed' do
        it 'does not output message' do
          allow(STDOUT).to receive(:closed?).and_return(true)
          expect(STDOUT).not_to receive(:puts)
          test_class.stdout('I', 'test message')
        end
      end
    end

    describe '#stderr' do
      context 'when STDERR is open' do
        it 'outputs formatted message' do
          expect(STDERR).to receive(:puts).with('E(1234567890): error message')
          test_class.stderr('E', 'error message')
        end
      end

      context 'when STDERR is closed' do
        it 'does not output message' do
          allow(STDERR).to receive(:closed?).and_return(true)
          expect(STDERR).not_to receive(:puts)
          test_class.stderr('E', 'error message')
        end
      end
    end
  end

  describe '#with_diagnostics' do
    context 'when diagnostics are enabled' do
      it 'executes the block' do
        allow(Onetime).to receive(:d9s_enabled).and_return(true)
        executed = false
        test_class.with_diagnostics { executed = true }
        expect(executed).to be true
      end
    end

    context 'when diagnostics are disabled' do
      it 'does not execute the block' do
        allow(Onetime).to receive(:d9s_enabled).and_return(false)
        executed = false
        test_class.with_diagnostics { executed = true }
        expect(executed).to be false
      end
    end
  end
end
