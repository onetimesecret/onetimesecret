# frozen_string_literal: true

# apps/web/billing/spec/support/shared_examples/cli_safety.rb
#
# Shared examples for testing CLI safety mechanisms

RSpec.shared_examples 'requires test mode for destructive operations' do |command_args|
  context 'when in production mode' do
    before do
      allow(OT).to receive(:conf).and_return(double(test_mode?: false))
    end

    it 'refuses to run' do
      output = run_cli_command_quietly(*command_args)

      expect(output[:stderr]).to match(/test mode/i)
      expect(last_exit_code).not_to eq(0)
    end

    it 'displays safety warning' do
      output = run_cli_command_quietly(*command_args)

      expect(output[:stderr]).to match(/safety|dangerous|production/i)
    end
  end

  context 'when in test mode' do
    before do
      allow(OT).to receive(:conf).and_return(double(test_mode?: true))
    end

    it 'allows the operation' do
      # This shared example only tests the safety check passes
      # Individual tests should mock the actual operation
      expect { run_cli_command_quietly(*command_args) }.not_to raise_error
    end
  end
end

RSpec.shared_examples 'supports dry-run mode' do |command_args|
  context 'with --dry-run flag' do
    it 'simulates the operation without executing' do
      dry_run_args = command_args + ['--dry-run']
      output = run_cli_command_quietly(*dry_run_args)

      expect(output[:stdout]).to match(/dry.?run|would|simulation/i)
      expect(output[:stdout]).not_to match(/completed|success|created/i)
    end

    it 'does not make API calls' do
      dry_run_args = command_args + ['--dry-run']

      expect(Stripe::Customer).not_to receive(:create)
      expect(Stripe::Customer).not_to receive(:update)
      expect(Stripe::Customer).not_to receive(:delete)

      run_cli_command_quietly(*dry_run_args)
    end

    it 'displays what would happen' do
      dry_run_args = command_args + ['--dry-run']
      output = run_cli_command_quietly(*dry_run_args)

      expect(output[:stdout]).to match(/would/)
      expect(last_exit_code).to eq(0)
    end
  end

  context 'without --dry-run flag' do
    it 'executes the actual operation' do
      # Individual tests should verify actual execution
      # This just ensures dry-run is not activated by default
      output = run_cli_command_quietly(*command_args)

      expect(output[:stdout]).not_to match(/dry.?run/i)
    end
  end
end

RSpec.shared_examples 'requires confirmation for dangerous operations' do |command_args|
  context 'without --force flag' do
    before do
      # Mock stdin to simulate user declining confirmation
      allow($stdin).to receive(:gets).and_return("n\n")
    end

    it 'prompts for confirmation' do
      output = run_cli_command_quietly(*command_args)

      expect(output[:stdout]).to match(/confirm|are you sure|proceed/i)
    end

    it 'aborts when user declines' do
      allow($stdin).to receive(:gets).and_return("n\n")
      output = run_cli_command_quietly(*command_args)

      expect(output[:stdout]).to match(/abort|cancel|skipp/i)
      expect(last_exit_code).not_to eq(0)
    end

    it 'proceeds when user confirms' do
      allow($stdin).to receive(:gets).and_return("y\n")

      # Individual tests should verify actual execution
      expect { run_cli_command_quietly(*command_args) }.not_to raise_error
    end
  end

  context 'with --force flag' do
    it 'skips confirmation prompt' do
      force_args = command_args + ['--force']
      output = run_cli_command_quietly(*force_args)

      expect(output[:stdout]).not_to match(/confirm|are you sure/i)
    end

    it 'executes immediately' do
      force_args = command_args + ['--force']

      # Should not prompt for input
      expect($stdin).not_to receive(:gets)

      run_cli_command_quietly(*force_args)
    end
  end
end

RSpec.shared_examples 'provides progress feedback' do |command_args, expected_steps: []|
  it 'displays progress indicators' do
    output = run_cli_command_quietly(*command_args)

    expect(output[:stdout]).to match(/processing|working|progress/i)
  end

  it 'shows completion status' do
    output = run_cli_command_quietly(*command_args)

    expect(output[:stdout]).to match(/complete|done|finish|success/i)
  end

  context 'when processing multiple items' do
    it 'shows item count' do
      output = run_cli_command_quietly(*command_args)

      expect(output[:stdout]).to match(/\d+\s+(of|\/)\s+\d+|\d+\s+items?/i)
    end
  end

  if expected_steps.any?
    it 'shows expected steps' do
      output = run_cli_command_quietly(*command_args)

      expected_steps.each do |step|
        expect(output[:stdout]).to match(/#{step}/i)
      end
    end
  end
end

RSpec.shared_examples 'handles errors gracefully' do |command_args|
  context 'when Stripe API fails' do
    before do
      allow(Stripe::Customer).to receive(:create).and_raise(
        Stripe::APIConnectionError.new('Network error')
      )
    end

    it 'displays user-friendly error message' do
      output = run_cli_command_quietly(*command_args)

      expect(output[:stderr]).to match(/error|fail/i)
      expect(output[:stderr]).not_to match(/backtrace|stack trace/i)
    end

    it 'exits with non-zero status' do
      run_cli_command_quietly(*command_args)

      expect(last_exit_code).not_to eq(0)
    end
  end

  context 'when validation fails' do
    it 'displays validation errors' do
      invalid_args = command_args.map { |arg| arg == 'valid_email@example.com' ? 'invalid' : arg }
      output = run_cli_command_quietly(*invalid_args)

      expect(output[:stderr]).to match(/invalid|error/i)
    end
  end
end

RSpec.shared_examples 'supports verbose output' do |command_args|
  context 'with --verbose flag' do
    it 'displays detailed information' do
      verbose_args = command_args + ['--verbose']
      output = run_cli_command_quietly(*verbose_args)

      # Verbose output should be more detailed
      expect(output[:stdout].length).to be > 0
    end

    it 'shows API request details' do
      verbose_args = command_args + ['--verbose']
      output = run_cli_command_quietly(*verbose_args)

      expect(output[:stdout]).to match(/request|api|stripe/i)
    end
  end

  context 'without --verbose flag' do
    it 'displays concise output' do
      output = run_cli_command_quietly(*command_args)

      # Should still have output, just less verbose
      expect(output[:stdout]).not_to be_empty
    end
  end
end
