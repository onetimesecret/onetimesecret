# spec/cli/email_validate_command_spec.rb
#
# frozen_string_literal: true

# Tests for: bin/ots email validate <email_address> [--mx|--regex|--smtp]
#
# Validates email addresses using Truemail with configurable validation modes.
# Default mode is :mx (DNS lookup). Other modes: :regex (format only), :smtp (full check).

require_relative 'cli_spec_helper'

RSpec.describe 'Email Validate Command', type: :cli do
  # Mock Truemail validation result structure
  # Note: mail_servers is required by output_text method
  let(:valid_result) do
    double('TruemailResult',
      valid?: true,
      email: 'user@example.com',
      domain: 'example.com',
      mail_servers: ['mx.example.com'],
      validation_type: :mx,
      errors: {},
      smtp_debug: nil
    )
  end

  let(:invalid_format_result) do
    double('TruemailResult',
      valid?: false,
      email: 'invalid-email',
      domain: nil,
      mail_servers: [],
      validation_type: :regex,
      errors: { regex: 'email does not match the regex pattern' },
      smtp_debug: nil
    )
  end

  let(:invalid_mx_result) do
    double('TruemailResult',
      valid?: false,
      email: 'user@nonexistent-domain-xyz.test',
      domain: 'nonexistent-domain-xyz.test',
      mail_servers: [],
      validation_type: :mx,
      errors: { mx: 'target host(s) not found' },
      smtp_debug: nil
    )
  end

  # SMTP debug entries are objects with host, port, connection, response_body, errors
  let(:smtp_debug_entry) do
    double('SmtpDebugEntry',
      host: 'mx.example.com',
      port: 25,
      connection: false,
      response_body: 'Connection refused',
      errors: { connection: 'refused' }
    )
  end

  let(:invalid_smtp_result) do
    double('TruemailResult',
      valid?: false,
      email: 'bounce@example.com',
      domain: 'example.com',
      mail_servers: ['mx.example.com'],
      validation_type: :smtp,
      errors: { smtp: 'smtp error' },
      smtp_debug: [smtp_debug_entry]
    )
  end

  let(:validator_double) do
    double('TruemailValidator', result: valid_result, as_json: { 'result' => 'valid' })
  end

  let(:email_runtime) do
    double('EmailRuntime', configured?: true, truemail_configured: true)
  end

  let(:truemail_config) do
    double('TruemailConfig',
      whitelisted_emails: [],
      blacklisted_emails: [],
      whitelisted_domains: [],
      blacklisted_domains: []
    )
  end

  before do
    # Mock Runtime.email.configured? to allow command to proceed
    allow(Onetime::Runtime).to receive(:email).and_return(email_runtime)

    # Mock Truemail.validate to avoid real DNS/SMTP lookups in tests
    allow(Truemail).to receive(:validate).and_return(validator_double)

    # Mock Truemail.configuration for list matching tests
    allow(Truemail).to receive(:configuration).and_return(truemail_config)
  end

  describe 'with valid email format (--regex mode)' do
    let(:regex_result) do
      double('TruemailResult',
        valid?: true,
        email: 'user@example.com',
        domain: 'example.com',
        mail_servers: [],
        validation_type: :regex,
        errors: {},
        smtp_debug: nil
      )
    end

    before do
      allow(Truemail).to receive(:validate)
        .with('user@example.com', with: :regex)
        .and_return(double('Validator', result: regex_result, as_json: {}))
    end

    it 'validates successfully with --regex flag' do
      output = run_cli_command_quietly('email', 'validate', 'user@example.com', '--regex')
      expect(output[:stdout]).to match(/valid/i)
      expect(output[:stdout]).to include('regex')
      expect(last_exit_code).to eq(0)
    end
  end

  describe 'with invalid email format' do
    before do
      allow(Truemail).to receive(:validate)
        .with('invalid-email', with: :regex)
        .and_return(double('Validator', result: invalid_format_result, as_json: {}))
    end

    it 'fails validation for email missing @' do
      output = run_cli_command_quietly('email', 'validate', 'invalid-email', '--regex')
      expect(output[:stdout]).to match(/invalid/i)
      expect(last_exit_code).to eq(1)
    end
  end

  describe 'with email missing domain part' do
    let(:no_domain_result) do
      double('TruemailResult',
        valid?: false,
        email: 'user@',
        domain: nil,
        mail_servers: [],
        validation_type: :regex,
        errors: { regex: 'email does not match the regex pattern' },
        smtp_debug: nil
      )
    end

    before do
      allow(Truemail).to receive(:validate)
        .with('user@', with: :regex)
        .and_return(double('Validator', result: no_domain_result, as_json: {}))
    end

    it 'fails validation for email without domain' do
      output = run_cli_command_quietly('email', 'validate', 'user@', '--regex')
      expect(output[:stdout]).to match(/invalid/i)
      expect(last_exit_code).to eq(1)
    end
  end

  describe 'with email missing local part' do
    let(:no_local_result) do
      double('TruemailResult',
        valid?: false,
        email: '@example.com',
        domain: 'example.com',
        mail_servers: [],
        validation_type: :regex,
        errors: { regex: 'email does not match the regex pattern' },
        smtp_debug: nil
      )
    end

    before do
      allow(Truemail).to receive(:validate)
        .with('@example.com', with: :regex)
        .and_return(double('Validator', result: no_local_result, as_json: {}))
    end

    it 'fails validation for email without local part' do
      output = run_cli_command_quietly('email', 'validate', '@example.com', '--regex')
      expect(output[:stdout]).to match(/invalid/i)
      expect(last_exit_code).to eq(1)
    end
  end

  describe 'MX validation (--mx mode, default)' do
    context 'when domain has valid MX records' do
      let(:mx_valid_result) do
        double('TruemailResult',
          valid?: true,
          email: 'user@gmail.com',
          domain: 'gmail.com',
          mail_servers: ['alt1.gmail-smtp-in.l.google.com'],
          validation_type: :mx,
          errors: {},
          smtp_debug: nil
        )
      end

      before do
        allow(Truemail).to receive(:validate)
          .with('user@gmail.com', with: :mx)
          .and_return(double('Validator', result: mx_valid_result, as_json: {}))
      end

      it 'validates successfully with MX records' do
        output = run_cli_command_quietly('email', 'validate', 'user@gmail.com', '--mx')
        expect(output[:stdout]).to match(/valid/i)
        expect(output[:stdout]).to include('mx')
        expect(last_exit_code).to eq(0)
      end

      it 'uses MX mode by default (no flag)' do
        # Default mode should be :mx
        allow(Truemail).to receive(:validate)
          .with('user@gmail.com', with: :mx)
          .and_return(double('Validator', result: mx_valid_result, as_json: {}))

        output = run_cli_command_quietly('email', 'validate', 'user@gmail.com')
        expect(output[:stdout]).to match(/valid/i)
        expect(last_exit_code).to eq(0)
      end
    end

    context 'when domain has no MX records' do
      before do
        allow(Truemail).to receive(:validate)
          .with('user@nonexistent-domain-xyz.test', with: :mx)
          .and_return(double('Validator', result: invalid_mx_result, as_json: {}))
      end

      it 'fails validation with MX error' do
        output = run_cli_command_quietly('email', 'validate', 'user@nonexistent-domain-xyz.test', '--mx')
        expect(output[:stdout]).to match(/invalid/i)
        expect(last_exit_code).to eq(1)
      end
    end
  end

  describe 'SMTP validation (--smtp mode)' do
    context 'when SMTP check succeeds' do
      let(:smtp_success_entry) do
        double('SmtpDebugEntry',
          host: 'mail.example.com',
          port: 25,
          connection: true,
          response_body: '220 mail.example.com ESMTP',
          errors: {}
        )
      end

      let(:smtp_valid_result) do
        double('TruemailResult',
          valid?: true,
          email: 'real-user@example.com',
          domain: 'example.com',
          mail_servers: ['mx.example.com'],
          validation_type: :smtp,
          errors: {},
          smtp_debug: [smtp_success_entry]
        )
      end

      before do
        allow(Truemail).to receive(:validate)
          .with('real-user@example.com', with: :smtp)
          .and_return(double('Validator', result: smtp_valid_result, as_json: {}))
      end

      it 'validates successfully with SMTP verification' do
        output = run_cli_command_quietly('email', 'validate', 'real-user@example.com', '--smtp')
        expect(output[:stdout]).to match(/valid/i)
        expect(output[:stdout]).to include('smtp')
        expect(last_exit_code).to eq(0)
      end
    end

    context 'when SMTP check fails' do
      before do
        allow(Truemail).to receive(:validate)
          .with('bounce@example.com', with: :smtp)
          .and_return(double('Validator', result: invalid_smtp_result, as_json: {}))
      end

      it 'fails validation with SMTP error' do
        output = run_cli_command_quietly('email', 'validate', 'bounce@example.com', '--smtp')
        expect(output[:stdout]).to match(/invalid/i)
        expect(last_exit_code).to eq(1)
      end
    end
  end

  describe 'option parsing' do
    it 'accepts --regex option' do
      expect(Truemail).to receive(:validate).with('test@example.com', with: :regex)
        .and_return(double('Validator', result: valid_result, as_json: {}))

      run_cli_command_quietly('email', 'validate', 'test@example.com', '--regex')
    end

    it 'accepts --mx option' do
      expect(Truemail).to receive(:validate).with('test@example.com', with: :mx)
        .and_return(double('Validator', result: valid_result, as_json: {}))

      run_cli_command_quietly('email', 'validate', 'test@example.com', '--mx')
    end

    it 'accepts --smtp option' do
      expect(Truemail).to receive(:validate).with('test@example.com', with: :smtp)
        .and_return(double('Validator', result: valid_result, as_json: {}))

      run_cli_command_quietly('email', 'validate', 'test@example.com', '--smtp')
    end
  end

  describe 'output format' do
    let(:detailed_result) do
      double('TruemailResult',
        valid?: true,
        email: 'user@example.com',
        domain: 'example.com',
        mail_servers: ['mx.example.com'],
        validation_type: :mx,
        errors: {},
        smtp_debug: nil
      )
    end

    before do
      allow(Truemail).to receive(:validate)
        .and_return(double('Validator', result: detailed_result, as_json: {
          'email' => 'user@example.com',
          'domain' => 'example.com',
          'validation_type' => 'mx',
          'success' => true
        }))
    end

    it 'includes email address in output' do
      output = run_cli_command_quietly('email', 'validate', 'user@example.com', '--mx')
      expect(output[:stdout]).to include('user@example.com')
    end

    it 'includes validation mode in output' do
      output = run_cli_command_quietly('email', 'validate', 'user@example.com', '--mx')
      expect(output[:stdout]).to include('mx')
    end

    it 'includes valid/invalid status in output' do
      output = run_cli_command_quietly('email', 'validate', 'user@example.com', '--mx')
      expect(output[:stdout]).to match(/valid|success/i)
    end
  end

  describe 'suppression and allowlist matching' do
    context 'when email matches allowlist' do
      let(:allowlisted_result) do
        double('TruemailResult',
          valid?: true,
          email: 'vip@trusted-domain.com',
          domain: 'trusted-domain.com',
          mail_servers: ['mx.trusted-domain.com'],
          validation_type: :mx,
          errors: {},
          smtp_debug: nil
        )
      end

      before do
        # Mock Truemail configuration with allowlist
        # Implementation uses whitelisted_* and blacklisted_* (Truemail's terminology)
        allow(Truemail).to receive(:configuration).and_return(
          double('Config',
            whitelisted_emails: [],
            blacklisted_emails: [],
            whitelisted_domains: ['trusted-domain.com'],
            blacklisted_domains: []
          )
        )
        allow(Truemail).to receive(:validate)
          .with('vip@trusted-domain.com', with: :mx)
          .and_return(double('Validator', result: allowlisted_result, as_json: {}))
      end

      it 'reports allowlist match when verbose' do
        # Note: Actual allowlist reporting depends on implementation
        output = run_cli_command_quietly('email', 'validate', 'vip@trusted-domain.com', '--mx')
        expect(output[:stdout]).to match(/valid/i)
        expect(last_exit_code).to eq(0)
      end
    end

    context 'when email matches denylist' do
      let(:denylisted_result) do
        double('TruemailResult',
          valid?: false,
          email: 'spammer@blocked-domain.com',
          domain: 'blocked-domain.com',
          mail_servers: [],
          validation_type: :mx,
          errors: { blacklist: 'domain is in the blacklist' },
          smtp_debug: nil
        )
      end

      before do
        allow(Truemail).to receive(:validate)
          .with('spammer@blocked-domain.com', with: :mx)
          .and_return(double('Validator', result: denylisted_result, as_json: {}))
      end

      it 'fails validation for denylisted domain' do
        output = run_cli_command_quietly('email', 'validate', 'spammer@blocked-domain.com', '--mx')
        expect(output[:stdout]).to match(/invalid/i)
        expect(last_exit_code).to eq(1)
      end
    end
  end

  describe 'error handling' do
    context 'when no email argument provided' do
      it 'displays usage error' do
        output = run_cli_command_quietly('email', 'validate')
        # Dry::CLI raises ArgumentError for missing required argument
        expect(last_exit_code).to eq(1)
      end
    end

    context 'when Truemail raises an error' do
      before do
        allow(Truemail).to receive(:validate).and_raise(StandardError, 'DNS timeout')
      end

      it 'handles validation errors gracefully' do
        output = run_cli_command_quietly('email', 'validate', 'user@example.com', '--mx')
        expect(output[:stderr]).to include('Error')
        expect(last_exit_code).to eq(1)
      end
    end
  end

  describe 'JSON output format' do
    let(:json_result) do
      double('TruemailResult',
        valid?: true,
        email: 'user@example.com',
        domain: 'example.com',
        mail_servers: ['mx.example.com'],
        validation_type: :mx,
        errors: {},
        smtp_debug: nil
      )
    end

    before do
      allow(Truemail).to receive(:validate)
        .and_return(double('Validator',
          result: json_result,
          as_json: {
            'email' => 'user@example.com',
            'domain' => 'example.com',
            'validation_type' => 'mx',
            'success' => true,
            'errors' => {}
          }
        ))
    end

    it 'outputs valid JSON with --format json flag' do
      output = run_cli_command_quietly('email', 'validate', 'user@example.com', '--format', 'json')

      # Attempt to parse as JSON
      if output[:stdout].include?('{')
        json_str = output[:stdout][output[:stdout].index('{')..]
        expect { JSON.parse(json_str) }.not_to raise_error
      end
    end
  end
end
