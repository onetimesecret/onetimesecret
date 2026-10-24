# spec/cli/write_gate_spec.rb
#
# frozen_string_literal: true

# The shared write gate (lib/onetime/cli/write_gate.rb): the option macro,
# the gate itself and the two report lines. Exercised on a throwaway command
# registered for the spec, so the behaviour is pinned independently of any
# one verb that includes it.
#
# Run: tests/lanes/run unit --only spec/cli/write_gate_spec.rb

require_relative 'cli_spec_helper'
require 'onetime/cli/write_gate'

RSpec.describe Onetime::CLI::WriteGate, type: :cli do
  def build_command(**macro_args)
    Class.new(Onetime::CLI::Command) do
      include Onetime::CLI::WriteGate

      write_gate_options('Write the thing', **macro_args)
      option :json, type: :boolean, default: false

      attr_reader :seen

      def call(apply: false, dry_run: false, json: false, **)
        @seen = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        if @seen
          dry_run_header
          puts 'would write the thing'
          dry_run_footer('write the thing')
        else
          puts 'wrote the thing'
        end
      end
    end
  end

  def option_named(klass, name)
    klass.params.find { |param| param.name == name }
  end

  describe '.write_gate_options' do
    it 'declares --apply with -y, --yes and -f, then --dry-run' do
      klass = build_command
      names = klass.params.map(&:name)

      expect(names.index(:apply)).to be < names.index(:dry_run)
      expect(option_named(klass, :apply).aliases).to eq(['-y', '--yes', '-f'])
      expect(option_named(klass, :apply).desc).to eq('Write the thing (default: dry run, nothing written)')
      expect(option_named(klass, :dry_run).desc).to include('contradicts --apply')
    end

    it 'leaves -f out for a command that uses it elsewhere' do
      klass = build_command(aliases: described_class::APPLY_ALIASES - ['-f'])

      expect(option_named(klass, :apply).aliases).to eq(['-y', '--yes'])
    end

    it 'extends the aliases for a flag the verb accepted before the gate' do
      klass = build_command(aliases: [*described_class::APPLY_ALIASES, '--run'])

      expect(option_named(klass, :apply).aliases).to eq(['-y', '--yes', '-f', '--run'])
    end

    it 'declares no alias when the verb passes none' do
      klass = build_command(aliases: [])

      expect(option_named(klass, :apply).aliases).to eq([])
    end
  end

  # A verb that narrows the aliases does so because another option owns the
  # flag (banner set: -f is --file). Pinned across every gated command, so a
  # call site that drops its narrowing fails here rather than letting two
  # options claim one flag.
  describe 'every command on the gate' do
    def flag_names(param)
      own = param.argument? ? [] : ["--#{param.name.to_s.tr('_', '-')}"]
      own + param.aliases.map do |name|
        bare = name.sub(/\A-{1,2}/, '')
        bare.size == 1 ? "-#{bare}" : "--#{bare}"
      end
    end

    let(:gated) do
      ObjectSpace.each_object(Class).select do |klass|
        klass < Onetime::CLI::Command && klass.include?(described_class) && klass.name
      end
    end

    it 'finds the gated verbs' do
      expect(gated.map(&:name)).to include(
        'Onetime::CLI::BannerSetCommand', 'Onetime::CLI::CustomersChangeEmailCommand',
        'Onetime::CLI::CustomersRoleReconcileCommand'
      )
    end

    it 'gives no other option a flag that --apply also claims' do
      clashes = gated.flat_map do |klass|
        apply = flag_names(klass.params.find { |param| param.name == :apply })
        klass.params.reject { |param| param.name == :apply }.flat_map do |param|
          (flag_names(param) & apply).map { |flag| "#{klass.name} #{flag} (--apply and :#{param.name})" }
        end
      end

      expect(clashes).to eq([])
    end
  end

  describe '#dry_run_unless_applied' do
    let(:command) { build_command.new }

    it 'is a dry run by default' do
      expect(command.dry_run_unless_applied(apply: false, dry_run: false, json: false)).to be(true)
    end

    it 'is a dry run when --dry-run only states the default' do
      expect(command.dry_run_unless_applied(apply: false, dry_run: true, json: false)).to be(true)
    end

    it 'writes with --apply' do
      expect(command.dry_run_unless_applied(apply: true, dry_run: false, json: false)).to be(false)
    end

    it 'exits 1 with a text error on --apply --dry-run' do
      output = capture_output do
        expect { command.dry_run_unless_applied(apply: true, dry_run: true, json: false) }
          .to raise_error(SystemExit) { |ex| expect(ex.status).to eq(1) }
      end

      expect(output[:stdout]).to include('Error: --apply and --dry-run are contradictory')
    end

    it 'keeps the error machine-readable under --json' do
      output = capture_output do
        expect { command.dry_run_unless_applied(apply: true, dry_run: true, json: true) }
          .to raise_error(SystemExit)
      end

      expect(JSON.parse(output[:stdout])['error']).to include('contradictory')
    end
  end

  describe 'the report lines' do
    let(:command) { build_command.new }

    it 'opens with the header and closes naming the flag that applies' do
      output = capture_output { command.call }

      expect(output[:stdout].lines.map(&:chomp)).to eq([
        'DRY RUN — nothing was written',
        'would write the thing',
        'Re-run with --apply to write the thing.',
      ])
    end

    it 'defaults the footer verb to "write"' do
      output = capture_output { command.dry_run_footer }

      expect(output[:stdout]).to eq("Re-run with --apply to write.\n")
    end
  end

  describe 'through Dry::CLI parsing' do
    it 'treats -y, --yes and -f as --apply' do
      klass = build_command
      ['-y', '--yes', '-f', '--apply'].each do |flag|
        cli    = Dry::CLI.new(Module.new { |m| m.extend(Dry::CLI::Registry); m.register('thing', klass) })
        output = capture_output { cli.call(arguments: ['thing', flag]) }

        expect(output[:stdout]).to eq("wrote the thing\n"), "#{flag} did not apply"
      end
    end

    it 'runs a bare invocation as a dry run' do
      klass  = build_command
      cli    = Dry::CLI.new(Module.new { |m| m.extend(Dry::CLI::Registry); m.register('thing', klass) })
      output = capture_output { cli.call(arguments: ['thing']) }

      expect(output[:stdout]).to start_with("DRY RUN — nothing was written\n")
    end
  end
end
