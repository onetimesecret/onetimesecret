# frozen_string_literal: true

require_relative '../../spec_helper'
require 'onetime/refinements/time_extensions'

RSpec.describe Onetime::TimeExtensions do
  using Onetime::TimeExtensions

  describe 'Numeric refinement' do
    describe 'time unit constants' do
      it 'defines correct time conversion constants' do
        expect(Onetime::TimeExtensions::PER_MICROSECOND).to eq(0.000001)
        expect(Onetime::TimeExtensions::PER_MILLISECOND).to eq(0.001)
        expect(Onetime::TimeExtensions::PER_MINUTE).to eq(60.0)
        expect(Onetime::TimeExtensions::PER_HOUR).to eq(3600.0)
        expect(Onetime::TimeExtensions::PER_DAY).to eq(86_400.0)
        expect(Onetime::TimeExtensions::PER_WEEK).to eq(604_800.0)
        expect(Onetime::TimeExtensions::PER_YEAR).to eq(31_536_000.0)
      end
    end

    describe 'base time unit conversions to seconds' do
      let(:base_value) { 2 }

      it 'converts microseconds to seconds' do
        expect(base_value.microseconds).to eq(2 * 0.000001)
        expect(base_value.microsecond).to eq(2 * 0.000001)
        expect(base_value.μs).to eq(2 * 0.000001)
      end

      it 'converts milliseconds to seconds' do
        expect(base_value.milliseconds).to eq(2 * 0.001)
        expect(base_value.millisecond).to eq(2 * 0.001)
        expect(base_value.ms).to eq(2 * 0.001)
      end

      it 'returns seconds as-is' do
        expect(base_value.seconds).to eq(2)
        expect(base_value.second).to eq(2)
      end

      it 'converts minutes to seconds' do
        expect(base_value.minutes).to eq(2 * 60)
        expect(base_value.minute).to eq(2 * 60)
      end

      it 'converts hours to seconds' do
        expect(base_value.hours).to eq(2 * 3600)
        expect(base_value.hour).to eq(2 * 3600)
      end

      it 'converts days to seconds' do
        expect(base_value.days).to eq(2 * 86_400)
        expect(base_value.day).to eq(2 * 86_400)
      end

      it 'converts weeks to seconds' do
        expect(base_value.weeks).to eq(2 * 604_800)
        expect(base_value.week).to eq(2 * 604_800)
      end

      it 'converts years to seconds' do
        expect(base_value.years).to eq(2 * 31_536_000)
        expect(base_value.year).to eq(2 * 31_536_000)
      end
    end

    describe 'seconds to other time unit conversions' do
      let(:seconds_value) { 7200 } # 2 hours

      it 'converts seconds to years' do
        expect(seconds_value.in_years).to eq(7200.0 / 31_536_000)
      end

      it 'converts seconds to weeks' do
        expect(seconds_value.in_weeks).to eq(7200.0 / 604_800)
      end

      it 'converts seconds to days' do
        expect(seconds_value.in_days).to eq(7200.0 / 86_400)
      end

      it 'converts seconds to hours' do
        expect(seconds_value.in_hours).to eq(2.0)
      end

      it 'converts seconds to minutes' do
        expect(seconds_value.in_minutes).to eq(120.0)
      end

      it 'converts seconds to milliseconds' do
        expect(seconds_value.in_milliseconds).to eq(7_200_000.0)
      end

      it 'converts seconds to microseconds' do
        expect(seconds_value.in_microseconds).to eq(7_200_000_000.0)
      end
    end

    describe 'time manipulation methods' do
      let(:base_seconds) { 3600 } # 1 hour
      let(:reference_time) { Time.at(1609459200) } # 2021-01-01 00:00:00 UTC
      let(:fixed_time) { Time.at(1609459200) } # 2021-01-01 00:00:00 UTC

      before(:each) do
        # Freeze time for consistent testing
        allow(Time).to receive(:now).and_return(fixed_time)
      end

      it 'calculates time ago from now' do
        result = base_seconds.ago
        expect(result).to eq(Time.now - 3600)
      end

      it 'calculates time from now' do
        result = base_seconds.from_now
        expect(result).to eq(Time.now + 3600)
      end

      it 'calculates time before a given time' do
        result = base_seconds.before(reference_time)
        expect(result).to eq(reference_time - 3600)
      end

      it 'calculates time after a given time' do
        result = base_seconds.after(reference_time)
        expect(result).to eq(reference_time + 3600)
      end

      it 'converts seconds to UTC time' do
        result = base_seconds.in_time
        expect(result).to eq(Time.at(3600).utc)
        expect(result.utc?).to be true
      end
    end

    describe '#to_ms' do
      it 'converts seconds to milliseconds' do
        expect(5.to_ms).to eq(5000.0)
        expect(1.5.to_ms).to eq(1500.0)
      end
    end

    describe '#in_seconds with units' do
      let(:base_value) { 2 }

      it 'converts to years when specified' do
        expect(base_value.in_seconds(:years)).to eq(2.years)
        expect(base_value.in_seconds('year')).to eq(2.years)
        expect(base_value.in_seconds('y')).to eq(2.years)
      end

      it 'converts to weeks when specified' do
        expect(base_value.in_seconds(:weeks)).to eq(2.weeks)
        expect(base_value.in_seconds('week')).to eq(2.weeks)
        expect(base_value.in_seconds('w')).to eq(2.weeks)
      end

      it 'converts to days when specified' do
        expect(base_value.in_seconds(:days)).to eq(2.days)
        expect(base_value.in_seconds('day')).to eq(2.days)
        expect(base_value.in_seconds('d')).to eq(2.days)
      end

      it 'converts to hours when specified' do
        expect(base_value.in_seconds(:hours)).to eq(2.hours)
        expect(base_value.in_seconds('hour')).to eq(2.hours)
        expect(base_value.in_seconds('h')).to eq(2.hours)
      end

      it 'converts to minutes when specified' do
        expect(base_value.in_seconds(:minutes)).to eq(2.minutes)
        expect(base_value.in_seconds('minute')).to eq(2.minutes)
        expect(base_value.in_seconds('m')).to eq(2.minutes)
      end

      it 'converts to milliseconds when specified' do
        expect(base_value.in_seconds(:milliseconds)).to eq(2.milliseconds)
        expect(base_value.in_seconds('millisecond')).to eq(2.milliseconds)
        expect(base_value.in_seconds('ms')).to eq(2.milliseconds)
      end

      it 'converts to microseconds when specified' do
        expect(base_value.in_seconds(:microseconds)).to eq(2.microseconds)
        expect(base_value.in_seconds('microsecond')).to eq(2.microseconds)
        expect(base_value.in_seconds('us')).to eq(2.microseconds)
        expect(base_value.in_seconds('μs')).to eq(2.microseconds)
      end

      it 'returns self for unrecognized units' do
        expect(base_value.in_seconds('invalid')).to eq(2)
        expect(base_value.in_seconds(nil)).to eq(2)
      end

      it 'demonstrates exactness behaviour' do
        # Only exact matches work as expected
        expect(base_value.in_seconds('m')).to eq(2.minutes)
        expect(base_value.in_seconds('m ')).to eq(base_value)
        expect(base_value.in_seconds('mm')).to eq(base_value)
        expect(base_value.in_seconds('min')).to eq(base_value)
      end
    end

    describe '#humanize' do
      it 'formats seconds correctly' do
        expect(1.humanize).to eq('1 second')
        expect(10.humanize).to eq('10 seconds')
        expect(59.humanize).to eq('59 seconds')
      end

      it 'formats minutes correctly' do
        expect(60.humanize).to eq('1 minute')
        expect(120.humanize).to eq('2 minutes')
        expect(3599.humanize).to eq('59 minutes')
      end

      it 'formats hours correctly' do
        expect(3600.humanize).to eq('1 hour')
        expect(7200.humanize).to eq('2 hours')
        expect(86_399.humanize).to eq('23 hours')
      end

      it 'formats days correctly' do
        expect(86_400.humanize).to eq('1 day')
        expect(172_800.humanize).to eq('2 days')
        expect(604_800.humanize).to eq('7 days')
      end

      it 'handles edge cases' do
        expect(0.humanize).to eq('0 seconds')
        expect((-1).humanize).to eq('1 second ago')
      end

      it 'handles floating point inputs by converting to integer' do
        expect(59.9.humanize).to eq('59 seconds')
        expect(60.1.humanize).to eq('1 minute')
      end
    end

    describe '#to_bytes' do
      it 'formats bytes correctly' do
        expect(512.to_bytes).to eq('512.00 B')
        expect(1023.to_bytes).to eq('1023.00 B')
      end

      it 'formats KiB correctly' do
        expect(1024.to_bytes).to eq('1024.00 B') # 1024 doesn't exceed threshold
        expect(2048.to_bytes).to eq('2.00 KiB')
        expect(1536.to_bytes).to eq('1.50 KiB')
      end

      it 'formats MiB correctly' do
        expect((1024 * 1024).to_bytes).to eq('1024.00 KiB') # exactly 1024 doesn't exceed threshold
        expect((2 * 1024 * 1024).to_bytes).to eq('2.00 MiB')
        expect((1.5 * 1024 * 1024).to_bytes).to eq('1.50 MiB')
      end

      it 'formats GiB correctly' do
        expect((1024 * 1024 * 1024).to_bytes).to eq('1024.00 MiB') # exactly 1024 doesn't exceed threshold
        expect((3 * 1024 * 1024 * 1024).to_bytes).to eq('3.00 GiB')
      end

      it 'formats TiB correctly' do
        expect((1024 * 1024 * 1024 * 1024).to_bytes).to eq('1024.00 GiB') # exactly 1024 doesn't exceed threshold
        expect((2.5 * 1024 * 1024 * 1024 * 1024).to_bytes).to eq('2.50 TiB')
      end

      it 'handles negative numbers' do
        expect((-1024).to_bytes).to eq('1024.00 B')
      end

      it 'handles zero' do
        expect(0.to_bytes).to eq('0.00 B')
      end

      it 'handles very large numbers' do
        huge_number = 1024**5
        result = huge_number.to_bytes
        expect(result).to match(/TiB$/)
      end
    end

    describe 'floating point precision' do
      it 'handles fractional time units' do
        expect(1.5.hours).to eq(5400.0)
        expect(2.5.days).to eq(216_000.0)
        expect(0.5.minutes).to eq(30.0)
      end

      it 'maintains precision in conversions' do
        expect(1.5.hours.in_minutes).to eq(90.0)
        expect(2.5.days.in_hours).to eq(60.0)
      end
    end
  end

  describe 'String refinement' do
    describe '#in_seconds' do
      it 'parses seconds correctly' do
        expect('30'.in_seconds).to eq(30.0)
        expect('30s'.in_seconds).to eq(30.0)
        expect('45.5'.in_seconds).to eq(45.5)
        expect('45.5s'.in_seconds).to eq(45.5)
      end

      it 'parses minutes correctly' do
        expect('5m'.in_seconds).to eq(300.0)
        expect('2.5m'.in_seconds).to eq(150.0)
        expect('60m'.in_seconds).to eq(3600.0)
      end

      it 'parses hours correctly' do
        expect('1h'.in_seconds).to eq(3600.0)
        expect('2.5h'.in_seconds).to eq(9000.0)
        expect('24h'.in_seconds).to eq(86_400.0)
      end

      it 'defaults to seconds when no unit specified' do
        expect('120'.in_seconds).to eq(120.0)
        expect('0'.in_seconds).to eq(0.0)
        expect('3.14'.in_seconds).to eq(3.14)
      end

      it 'returns nil for invalid formats' do
        expect(''.in_seconds).to be_nil
        expect('abc'.in_seconds).to be_nil
        expect('m30'.in_seconds).to eq(30.0) # regex matches "30" with unit defaulting to 's'
        expect('30x'.in_seconds).to eq(30.0) # regex matches "30" with unit defaulting to 's'
      end

      it 'handles edge cases' do
        expect('0s'.in_seconds).to eq(0.0)
        expect('0m'.in_seconds).to eq(0.0)
        expect('0h'.in_seconds).to eq(0.0)
      end

      it 'handles various numeric formats' do
        expect('.5m'.in_seconds).to eq(30.0)
        expect('1.0h'.in_seconds).to eq(3600.0)
        expect('10.0'.in_seconds).to eq(10.0)
      end

      it 'demonstrates regex parsing behavior' do
        # The regex /([\d.]+)([smh])?/ extracts number and optional unit
        # If no unit is matched or unit is nil, it defaults to 's' (seconds)
        expect('123'.in_seconds).to eq(123.0) # no unit, defaults to seconds
        expect('123s'.in_seconds).to eq(123.0) # explicit seconds
        expect('123m'.in_seconds).to eq(7380.0) # minutes to seconds
        expect('123h'.in_seconds).to eq(442800.0) # hours to seconds

        # Invalid unit characters are ignored, defaults to seconds
        expect('123x'.in_seconds).to eq(123.0) # 'x' not in [smh], defaults to seconds
        expect('123z'.in_seconds).to eq(123.0) # 'z' not in [smh], defaults to seconds
      end

      it 'handles complex parsing edge cases' do
        # Multiple digits and units - only first match is used
        expect('12.5m30s'.in_seconds).to eq(750.0) # only '12.5m' is parsed
        expect('1h2m3s'.in_seconds).to eq(3600.0) # only '1h' is parsed

        # Leading/trailing text is ignored
        expect('time: 30m remaining'.in_seconds).to eq(1800.0) # extracts '30m'
        expect('wait 5s please'.in_seconds).to eq(5.0) # extracts '5s'
      end
    end

    describe 'integration with Numeric methods' do
      it 'can chain string parsing with numeric time methods' do
        parsed_seconds = '2h'.in_seconds
        expect(parsed_seconds.in_minutes).to eq(120.0)
        expect(parsed_seconds.humanize).to eq('2 hours')
      end
    end
  end

  describe 'edge cases and error handling' do
    it 'handles very large numbers' do
      large_num = 999_999_999
      expect { large_num.seconds }.not_to raise_error
      expect { large_num.humanize }.not_to raise_error
      expect { large_num.to_bytes }.not_to raise_error
    end

    it 'handles very small numbers' do
      small_num = 0.000001
      expect { small_num.seconds }.not_to raise_error
      expect { small_num.microseconds }.not_to raise_error
    end

    it 'handles negative numbers appropriately' do
      expect((-60).humanize).to eq('1 minute ago')
      expect((-3600).in_hours).to eq(-1.0)
    end

    it 'handles floating point precision edge cases' do
      # Test precision with very small fractional values
      expect(0.001.seconds).to eq(0.001)
      expect(0.000001.microseconds).to eq(1e-12)

      # Test precision with large fractional values
      expect(1.999999.hours).to be_within(0.001).of(7199.996)
      expect(365.25.days).to eq(31_557_600.0) # leap year consideration
    end

    it 'handles special numeric values' do
      # Test infinity and NaN behavior (should not raise errors)
      expect { Float::INFINITY.seconds }.not_to raise_error
      expect { (-Float::INFINITY).seconds }.not_to raise_error

      # NaN will produce NaN results but shouldn't crash
      expect { (0.0/0.0).seconds }.not_to raise_error
    end

    it 'demonstrates humanize edge case behavior' do
      # Negative numbers have unexpected behavior due to case statement logic
      expect((-1).humanize).to eq('1 second ago') # uses positive logic
      expect((-59).humanize).to eq('59 seconds ago') # uses positive logic
      expect((-3599).humanize).to eq('59 minutes ago') # uses positive logic

      # Large numbers are converted to days
      expect(86401.humanize).to eq('1 day') # just over 1 day
      expect(172801.humanize).to eq('2 days') # just over 2 days
    end
  end

  describe 'compatibility and refinement scoping' do
    it 'refinement works within the current scope' do
      # This test ensures the refinement is active in this scope
      expect(5.seconds).to eq(5)
      expect(10.minutes).to eq(600)
    end

    it 'works with different numeric types' do
      # Test with integers
      expect(5.seconds).to eq(5)
      expect(10.minutes).to eq(600)

      # Test with floats
      expect(2.5.hours).to eq(9000.0)
      expect(1.5.days).to eq(129_600.0)

      # Test with rational numbers
      expect(Rational(3, 2).hours).to eq(5400.0)
    end

    it 'maintains method chaining capability' do
      # Test chaining time methods
      result = 2.hours.in_minutes
      expect(result).to eq(120.0)

      # Test chaining with time manipulation
      now = Time.now
      allow(Time).to receive(:now).and_return(now)
      expect(1.hour.ago).to eq(now - 3600)
      expect(30.minutes.from_now).to eq(now + 1800)
    end
  end
end
