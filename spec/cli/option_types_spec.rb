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
  # option and the leaf defines its own `call`. Params are inherited, so the
  # dispatch hook sees `count` even though the leaf never declares it.
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

  describe 'a leaf command whose option is declared on an intermediate base' do
    it 'still coerces' do
      run(registry, 'leaf', '--count', '9')
      expect(leaf_command.received[:count]).to eq(9).and be_a(Integer)
    end
  end

  # Coverage is structural: the hook sits in dispatch, so a command reaches
  # `call` coerced whether or not it descends from a project base class.
  # Onetime::CLI::SessionCommand subclasses Dry::CLI::Command directly and is
  # covered for exactly this reason.
  describe 'a command that subclasses Dry::CLI::Command directly' do
    let(:bare_command) do
      Class.new(Dry::CLI::Command) do
        class << self; attr_accessor :received; end

        option :limit, type: :integer, default: 20

        def call(**args)
          self.class.received = args
        end
      end
    end

    let(:registry) do
      reg = Module.new { extend Dry::CLI::Registry }
      reg.register 'bare', bare_command
      reg
    end

    it 'does not inherit from either project base class' do
      expect(bare_command.ancestors).not_to include(Onetime::CLI::Command)
    end

    it 'is still coerced' do
      run(registry, 'bare', '--limit', '7')
      expect(bare_command.received[:limit]).to eq(7).and be_a(Integer)
    end
  end

  # Everything above drives throwaway classes. This drives a real registered
  # command with a real `type: :integer` declaration, through the real registry
  # dispatch, down to the Operation that receives the value.
  describe 'the real domains probe command' do
    let(:registry) do
      reg = Module.new { extend Dry::CLI::Registry }
      reg.register 'probe', Onetime::CLI::DomainsProbeCommand
      reg
    end

    # A Struct rather than a double: the command only needs #display_domain, and
    # Onetime::CustomDomain may itself be stubbed out by cli_spec_helper.
    let(:domain) { Struct.new(:display_domain).new('example.com') }

    before do
      probe_op = instance_double(Onetime::Operations::Domains::Probe, call: { health: 'healthy' })

      allow_any_instance_of(Onetime::CLI::DomainsProbeCommand) # rubocop:disable RSpec/AnyInstance
        .to receive(:resolve_domain).and_return(domain)
      allow(Onetime::Operations::Domains::Probe).to receive(:new).and_return(probe_op)
    end

    it 'hands the operation an Integer timeout' do
      run(registry, 'probe', 'example.com', '--timeout', '30', '--json')

      expect(Onetime::Operations::Domains::Probe)
        .to have_received(:new).with(hash_including(timeout: 30))
    end

    it 'exits 1 on non-numeric input without reaching the operation' do
      result = run(registry, 'probe', 'example.com', '--timeout', 'abc')

      expect(result[:exit_code]).to eq(1)
      expect(result[:stdout]).to include('--timeout must be an integer (got "abc")')
      expect(Onetime::Operations::Domains::Probe).not_to have_received(:new)
    end
  end

  # The hook leaves command classes untouched, which several tryouts depend on:
  # they read `instance_method(:call).parameters` for the declared keyword names
  # and `.source_location` to assert on the command's own source text.
  describe 'command ancestor chains' do
    it 'leaves a command\'s own #call at the head of its chain' do
      expect(probe_command.instance_method(:call).owner).to eq(probe_command)
      expect(probe_command.instance_method(:call).source_location.first)
        .to eq(__FILE__)
    end
  end

  # Dry::CLI#parse is @api private. If a gem upgrade renames it or changes its
  # return shape, coercion would stop happening silently -- fail here instead.
  describe 'the dry-cli integration point' do
    let(:hook) { described_class::Dispatch }

    it 'is installed ahead of Dry::CLI' do
      expect(Dry::CLI.ancestors.index(hook)).to be < Dry::CLI.ancestors.index(Dry::CLI)
    end

    it 'overrides a real Dry::CLI method with the expected signature' do
      overridden = Dry::CLI.instance_method(:parse).super_method

      expect(overridden.owner).to eq(Dry::CLI)
      expect(overridden.parameters).to eq([[:req, :command], [:req, :arguments], [:req, :names]])
    end

    it 'is reached from both dispatch entry points' do
      source = File.read(Dry::CLI.instance_method(:parse).super_method.source_location.first)

      expect(source).to include('def perform_command').and include('def perform_registry')
      expect(source.scan('command, args = parse(').length).to eq(2)
    end
  end
end
