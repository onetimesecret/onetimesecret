# apps/api/v1/spec/logic/secrets/v1_validation_boundaries_spec.rb
#
# frozen_string_literal: true

# V1 Validation Boundary Tests [#2621]
#
# Verifies that V1 API preserves v0.23.4 validation behavior:
#   - TTL: 60s minimum, 30-day maximum (silently clamped)
#   - Passphrase: no minimum length enforced, optional by default
#   - Email: format-only validation (no DNS/SMTP checks)
#   - Secret size: 10,000 character maximum enforced
#   - Error responses: {"message": "..."} with HTTP 404

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')

# Test subclass that implements the required abstract method
class V1BoundaryTestAction < V1::Logic::Secrets::BaseSecretAction
  def process_secret
    @kind = :test
    @secret_value = "test_secret"
  end
end

# Test subclass with controllable secret_value for size tests
class V1SizeTestAction < V1::Logic::Secrets::BaseSecretAction
  attr_writer :secret_value

  def process_secret
    @kind = :test
    @secret_value ||= "test_secret"
  end
end

RSpec.describe 'V1 Validation Boundaries [#2621]' do
  using Familia::Refinements::TimeLiterals

  let(:customer) {
    double('Customer',
      anonymous?: false,
      custid: 'cust123',
      objid: 'obj123',
      planid: 'anonymous')
  }

  let(:session) {
    double('Session',
      anonymous?: false,
      custid: 'cust123')
  }

  let(:base_params) {
    {
      'recipient'    => [],
      'share_domain' => '',
    }
  }

  before(:all) do
    OT.boot!(:test)
  end

  before do
    allow(Truemail).to receive(:validate).and_return(
      double('Validator', result: double('Result', valid?: true), as_json: '{}'),
    )
  end

  # =========================================================================
  # TTL Validation Boundaries
  # =========================================================================
  describe 'TTL boundaries' do
    describe 'V1 constants' do
      it 'defines V1_MIN_TTL as 60 seconds (v0.23.4 compatible)' do
        expect(V1::Logic::Secrets::BaseSecretAction::V1_MIN_TTL).to eq(60)
      end

      it 'defines V1_MAX_TTL as 30 days' do
        expect(V1::Logic::Secrets::BaseSecretAction::V1_MAX_TTL).to eq(2_592_000)
      end
    end

    describe '#process_ttl' do
      subject { V1BoundaryTestAction.new(session, customer, base_params) }

      it 'accepts ttl=60 (1 minute) — v0.23.4 minimum' do
        subject.instance_variable_set(:@payload, { 'ttl' => '60' })
        subject.send(:process_ttl)
        expect(subject.ttl).to eq(60)
      end

      it 'accepts ttl=300 (5 minutes)' do
        subject.instance_variable_set(:@payload, { 'ttl' => '300' })
        subject.send(:process_ttl)
        expect(subject.ttl).to eq(300)
      end

      it 'accepts ttl=1800 (30 minutes)' do
        subject.instance_variable_set(:@payload, { 'ttl' => '1800' })
        subject.send(:process_ttl)
        expect(subject.ttl).to eq(1800)
      end

      it 'clamps ttl below V1_MIN_TTL up to 60' do
        subject.instance_variable_set(:@payload, { 'ttl' => '5' })
        subject.send(:process_ttl)
        expect(subject.ttl).to eq(60)
      end

      it 'clamps ttl=0 up to V1_MIN_TTL' do
        subject.instance_variable_set(:@payload, { 'ttl' => '0' })
        subject.send(:process_ttl)
        expect(subject.ttl).to eq(60)
      end

      it 'clamps ttl above V1_MAX_TTL down to 30 days' do
        subject.instance_variable_set(:@payload, { 'ttl' => '3000000' })
        subject.send(:process_ttl)
        expect(subject.ttl).to be <= 2_592_000
      end

      it 'accepts ttl=2592000 (exactly 30 days)' do
        subject.instance_variable_set(:@payload, { 'ttl' => '2592000' })
        subject.send(:process_ttl)
        expect(subject.ttl).to eq(2_592_000)
      end

      it 'clamps ttl=2678400 (31 days) down' do
        subject.instance_variable_set(:@payload, { 'ttl' => '2678400' })
        subject.send(:process_ttl)
        expect(subject.ttl).to be <= 2_592_000
      end

      it 'uses config default_ttl when none provided' do
        subject.instance_variable_set(:@payload, {})
        subject.send(:process_ttl)
        # Should use config default, not reject
        expect(subject.ttl).to be > 0
      end
    end
  end

  # =========================================================================
  # Passphrase Validation Boundaries
  # =========================================================================
  describe 'Passphrase boundaries' do
    describe '.passphrase_min_length (config-driven) [#2758]' do
      it 'returns nil when config has no minimum_length set' do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'secret_options' => {
              'passphrase' => {}
            }
          }
        })
        expect(V1::Logic::Secrets::BaseSecretAction.passphrase_min_length).to be_nil
      end

      it 'returns nil when passphrase config is missing entirely' do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'secret_options' => {}
          }
        })
        expect(V1::Logic::Secrets::BaseSecretAction.passphrase_min_length).to be_nil
      end

      it 'returns the configured minimum_length when set' do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'secret_options' => {
              'passphrase' => {
                'minimum_length' => 8
              }
            }
          }
        })
        expect(V1::Logic::Secrets::BaseSecretAction.passphrase_min_length).to eq(8)
      end
    end

    describe '#validate_passphrase' do
      subject { V1BoundaryTestAction.new(session, customer, base_params) }

      context 'when no minimum_length configured (default/backward-compatible)' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'secret_options' => {
                'passphrase' => {
                  'maximum_length' => 128
                }
              }
            }
          })
        end

        it 'accepts 4-character passphrase (v0.23.4 compat)' do
          subject.instance_variable_set(:@passphrase, 'abcd')
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end

        it 'accepts 1-character passphrase' do
          subject.instance_variable_set(:@passphrase, 'a')
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end

        it 'accepts empty passphrase (optional)' do
          subject.instance_variable_set(:@passphrase, '')
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end

        it 'accepts nil passphrase (optional)' do
          subject.instance_variable_set(:@passphrase, nil)
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end

        it 'accepts 8-character passphrase' do
          subject.instance_variable_set(:@passphrase, 'abcdefgh')
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end
      end

      context 'when minimum_length: 8 configured (opt-in enforcement)' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'secret_options' => {
                'passphrase' => {
                  'minimum_length' => 8,
                  'maximum_length' => 128
                }
              }
            }
          })
        end

        it 'rejects 4-character passphrase' do
          subject.instance_variable_set(:@passphrase, 'abcd')
          expect { subject.send(:validate_passphrase) }.to raise_error(
            OT::FormError, /at least 8 characters/
          )
        end

        it 'rejects 7-character passphrase (just under minimum)' do
          subject.instance_variable_set(:@passphrase, 'abcdefg')
          expect { subject.send(:validate_passphrase) }.to raise_error(
            OT::FormError, /at least 8 characters/
          )
        end

        it 'accepts 8-character passphrase (exactly at minimum)' do
          subject.instance_variable_set(:@passphrase, 'abcdefgh')
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end

        it 'accepts 12-character passphrase (above minimum)' do
          subject.instance_variable_set(:@passphrase, 'abcdefghijkl')
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end

        it 'still accepts empty passphrase (optional unless required: true)' do
          subject.instance_variable_set(:@passphrase, '')
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end

        it 'still accepts nil passphrase (optional unless required: true)' do
          subject.instance_variable_set(:@passphrase, nil)
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end
      end

      context 'when minimum_length: 4 configured' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'secret_options' => {
                'passphrase' => {
                  'minimum_length' => 4,
                  'maximum_length' => 128
                }
              }
            }
          })
        end

        it 'rejects 3-character passphrase' do
          subject.instance_variable_set(:@passphrase, 'abc')
          expect { subject.send(:validate_passphrase) }.to raise_error(
            OT::FormError, /at least 4 characters/
          )
        end

        it 'accepts 4-character passphrase (exactly at minimum)' do
          subject.instance_variable_set(:@passphrase, 'abcd')
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end
      end

      context 'maximum length validation' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'secret_options' => {
                'passphrase' => {
                  'maximum_length' => 128
                }
              }
            }
          })
        end

        it 'rejects passphrase exceeding maximum length' do
          subject.instance_variable_set(:@passphrase, 'a' * 200)
          expect { subject.send(:validate_passphrase) }.to raise_error(
            OT::FormError, /no more than/
          )
        end
      end

      context 'complexity enforcement' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'secret_options' => {
                'passphrase' => {
                  'enforce_complexity' => true,
                  'maximum_length' => 128
                }
              }
            }
          })
        end

        it 'does not enforce complexity for V1 (ignores config)' do
          # Even with simple passphrase (no uppercase, symbols, etc.)
          # and enforce_complexity: true in config, V1 API ignores it
          subject.instance_variable_set(:@passphrase, 'simplepassword')
          expect { subject.send(:validate_passphrase) }.not_to raise_error
        end
      end
    end
  end

  # =========================================================================
  # Email Validation Boundaries
  # =========================================================================
  describe 'Email validation (Truemail)' do
    subject { V1BoundaryTestAction.new(session, customer, base_params) }

    before do
      # Override the global Truemail stub so real validation runs
      # (uses :regex type per spec/config.test.yaml)
      allow(Truemail).to receive(:validate).and_call_original
    end

    it 'accepts standard email format' do
      expect(subject.valid_email?('user@example.com')).to be true
    end

    it 'accepts email with subdomain' do
      expect(subject.valid_email?('user@mail.example.com')).to be true
    end

    it 'accepts email with plus addressing' do
      expect(subject.valid_email?('user+tag@example.com')).to be true
    end

    it 'rejects email without @' do
      expect(subject.valid_email?('userexample.com')).to be false
    end

    it 'rejects email without domain' do
      expect(subject.valid_email?('user@')).to be false
    end

    it 'rejects empty string' do
      expect(subject.valid_email?('')).to be false
    end
  end

  # =========================================================================
  # Secret Size Boundaries
  # =========================================================================
  describe 'Secret size boundaries' do
    describe 'V1 constants' do
      it 'defines V1_MAX_SECRET_SIZE as 10000' do
        expect(V1::Logic::Secrets::BaseSecretAction::V1_MAX_SECRET_SIZE).to eq(10_000)
      end
    end

    describe '#validate_secret_size' do
      subject { V1SizeTestAction.new(session, customer, base_params) }

      it 'accepts secret under the limit' do
        subject.secret_value = 'a' * 1000
        expect { subject.send(:validate_secret_size) }.not_to raise_error
      end

      it 'accepts secret at exactly the limit' do
        subject.secret_value = 'a' * 10_000
        expect { subject.send(:validate_secret_size) }.not_to raise_error
      end

      it 'rejects secret exceeding the limit' do
        subject.secret_value = 'a' * 10_001
        expect { subject.send(:validate_secret_size) }.to raise_error(
          OT::FormError, /exceeds the maximum size/
        )
      end

      it 'accepts nil secret value' do
        subject.secret_value = nil
        expect { subject.send(:validate_secret_size) }.not_to raise_error
      end
    end
  end

end
