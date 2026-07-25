# spec/cli/option_types_spec.rb
#
# frozen_string_literal: true

require_relative 'cli_spec_helper'

# Dry::CLI 1.4.1 silently ignores `type: :integer` / `type: :float` -- see
# lib/onetime/cli/option_types.rb. These specs pin the coercion that makes those
# declarations mean what every call site already assumes.
RSpec.describe Onetime::CLI::OptionTypes, type: :cli do
  # Commands are driven through a throwaway registry so nothing here mutates the
  # real Onetime::CLI command tree.
  def run(registry, *args)
    exit_code = 0
    output = capture_output do
      Dry::CLI.new(registry).call(arguments: args)
    rescue SystemExit => e
      exit_code = e.status
    end
    output.merge(exit_code: exit_code)
  end

  let(:registry) do
    reg = Module.new { extend Dry::CLI::Registry }
    reg.register 'probe', probe_command
    reg.register 'leaf', leaf_command
    reg
  end

  let(:probe_command) do
    Class.new(Onetime::CLI::Command) do
      class << self; attr_accessor :received; end

      option :limit, type: :integer, default: 20
      option :ratio, type: :float, default: 0.5
      option :label, type: :string, default: 'unset'
      option :json, type: :boolean, default: false
      option :maybe, type: :integer, default: nil

      def call(**args)
        self.class.received = args
      end
    end
  end

  # Mirrors DlqListCommand < DlqBase < Command: an intermediate base declares the
  # option and the leaf defines its own `call`.
  let(:base_command) do
    Class.new(Onetime::CLI::Command) do
      option :count, type: :integer, default: 3
    end
  end

  let(:leaf_command) do
    Class.new(base_command) do
      class << self; attr_accessor :received; end

      def call(**args)
        self.class.received = args
      end
    end
  end

  describe 'integer coercion' do
    it 'converts a supplied flag from String to Integer' do
      run(registry, 'probe', '--limit', '30')
      expect(probe_command.received[:limit]).to eq(30).and be_a(Integer)
    end

    it 'leaves an omitted flag as its declared Integer default' do
      run(registry, 'probe')
      expect(probe_command.received[:limit]).to eq(20).and be_a(Integer)
    end

    # Kernel#Integer honours literal prefixes when no base is given, so a
    # zero-padded value would otherwise be read as octal: Integer("010") == 8.
    it 'parses base 10, not octal, for zero-padded input' do
      run(registry, 'probe', '--limit', '010')
      expect(probe_command.received[:limit]).to eq(10)
    end

    it 'rejects a hex literal rather than silently accepting it' do
      result = run(registry, 'probe', '--limit', '0x1e')
      expect(result[:exit_code]).to eq(1)
      expect(result[:stdout]).to include('--limit must be an integer')
    end

    it 'accepts a negative value' do
      run(registry, 'probe', '--limit=-5')
      expect(probe_command.received[:limit]).to eq(-5)
    end

    it 'accepts zero without treating it as a coercion failure' do
      run(registry, 'probe', '--limit', '0')
      expect(probe_command.received[:limit]).to eq(0)
    end

    # `default: nil` means "unset" and several commands branch on exactly that,
    # so nil must not become 0.
    it 'leaves a nil default as nil' do
      run(registry, 'probe')
      expect(probe_command.received[:maybe]).to be_nil
    end
  end

  describe 'float coercion' do
    it 'converts a supplied flag from String to Float' do
      run(registry, 'probe', '--ratio', '1.5')
      expect(probe_command.received[:ratio]).to eq(1.5).and be_a(Float)
    end

    it 'rejects non-numeric input' do
      result = run(registry, 'probe', '--ratio', 'fast')
      expect(result[:exit_code]).to eq(1)
      expect(result[:stdout]).to include('--ratio must be a number')
    end
  end

  describe 'invalid input' do
    it 'exits 1 and does not reach call' do
      probe_command.received = nil
      result = run(registry, 'probe', '--limit', 'abc')

      expect(result[:exit_code]).to eq(1)
      expect(result[:stdout]).to include('--limit must be an integer (got "abc")')
      expect(probe_command.received).to be_nil
    end

    it 'emits the JSON error shape when --json is set' do
      result = run(registry, 'probe', '--limit', 'abc', '--json')

      expect(result[:exit_code]).to eq(1)
      expect(JSON.parse(result[:stdout])).to eq('error' => '--limit must be an integer (got "abc")')
    end
  end

  describe 'non-numeric options' do
    it 'leaves string and boolean options untouched' do
      run(registry, 'probe', '--label', '42', '--json')

      expect(probe_command.received[:label]).to eq('42')
      expect(probe_command.received[:json]).to be(true)
    end
  end

  # A prepended module only precedes the methods of the class it is prepended
  # to, so prepending to the intermediate base alone would leave the leaf's own
  # `call` ahead of the coercion in the ancestor chain.
  describe 'a leaf command whose option is declared on an intermediate base' do
    it 'still coerces' do
      run(registry, 'leaf', '--count', '9')
      expect(leaf_command.received[:count]).to eq(9).and be_a(Integer)
    end
  end

  # Regression guard for the whole class of defect: a new command that skips
  # both project base classes would silently reintroduce it.
  describe 'coverage across the real command tree' do
    it 'coerces every declared numeric param on every registered command' do
      # Singleton classes of command instances (RSpec creates one whenever it
      # stubs a method on an instance) satisfy `< Dry::CLI::Command` but never
      # ran through `Dry::CLI::Command.inherited`, so they have no @_mutex and
      # `params` raises. They are not commands.
      commands = ObjectSpace.each_object(Class).select do |klass|
        klass < Dry::CLI::Command && !klass.singleton_class?
      end

      uncovered = commands.filter_map do |klass|
        numeric = klass.params.select { |param| %i[integer float].include?(param.type) }
        next if numeric.empty?
        next if klass.ancestors.include?(described_class::Coercion)

        "#{klass}: #{numeric.map(&:name).join(', ')}"
      end

      expect(uncovered).to be_empty
    end
  end
end
