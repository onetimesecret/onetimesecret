# spec/unit/lanes/workers_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../tests/lanes/support/workers'

# Lanes::Workers (#4551): the two lane runner variables lib/tasks/spec.rake
# needs for a split run, read here so the rake file, which is copied into
# the image, names no lane runner variable itself
# (image_log_defaults_guard_spec.rb). The module is given a hash; nothing
# here runs a lane.
RSpec.describe Lanes::Workers do
  describe '.count' do
    it 'is 1 when the variable is unset or empty' do
      expect(described_class.count({})).to eq(1)
      expect(described_class.count('LANES_WORKERS' => '')).to eq(1)
      expect(described_class.count('LANES_WORKERS' => '  ')).to eq(1)
    end

    it 'is the count the runner exported' do
      expect(described_class.count('LANES_WORKERS' => '4')).to eq(4)
      expect(described_class.count('LANES_WORKERS' => ' 2 ')).to eq(2)
    end

    it 'refuses zero, a negative count and a non-number, naming the variable' do
      %w[0 -1 x 2.5].each do |value|
        expect { described_class.count('LANES_WORKERS' => value) }
          .to raise_error(ArgumentError, "LANES_WORKERS must be a positive integer, not #{value.inspect}")
      end
    end

    it 'does not change the environment it is given' do
      env = { 'LANES_WORKERS' => '3' }.freeze

      expect { described_class.count(env) }.not_to raise_error
    end
  end

  describe '.status_file' do
    it 'is nil when the variable is unset or empty' do
      expect(described_class.status_file({})).to be_nil
      expect(described_class.status_file('LANES_RSPEC_STATUS_FILE' => '')).to be_nil
    end

    it 'is the path the runner exported' do
      expect(described_class.status_file('LANES_RSPEC_STATUS_FILE' => '/x/tmp/lanes/simple/base/rspec-status.txt'))
        .to eq('/x/tmp/lanes/simple/base/rspec-status.txt')
    end
  end
end
