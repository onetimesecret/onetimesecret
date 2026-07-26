# apps/api/v2/spec/logic/secrets/generate_secret_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Regression coverage for the C5 generate-length DoS.
#
# POST /api/v2/secret/generate reads `secret[length]` from the payload. The
# allocating call `Onetime::Utils.strand(length, ...)` runs inside
# process_secret, which fires from process_params in the LOGIC CONSTRUCTOR —
# BEFORE raise_concerns. So the ceiling must be enforced in process_secret,
# immediately before strand, or the oversized string is already allocated.
#
# These tests drive process_params directly (constructor path) and assert:
#   1. an oversized `length` is rejected before strand ever allocates;
#   2. a payload attempting to raise the ceiling via secret[maximum_length]
#      is STILL rejected (config ceiling wins over payload);
#   3. a normal length succeeds and yields a secret_value of the expected size.
RSpec.describe V2::Logic::Secrets::GenerateSecret, type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  def mock_session
    store = {}
    session = double('Session')
    allow(session).to receive(:[]) { |k| store[k] }
    allow(session).to receive(:[]=) { |k, v| store[k] = v }
    session
  end

  # Build a GenerateSecret over an anonymous caller. We exercise process_params
  # (constructor-time allocation path), not raise_concerns.
  def build_logic(secret_params)
    customer = double('Customer', custid: 'anon', anonymous?: true, objid: nil)
    org      = double('Organization', objid: "org_#{SecureRandom.hex(4)}")
    allow(org).to receive(:can?).and_return(true)
    allow(org).to receive(:limit_for).and_return(0)

    strategy_result = double('StrategyResult',
      session: mock_session,
      user: customer,
      metadata: { organization: org, ip: '203.0.113.7' },
      auth_method: 'basicauth')

    described_class.new(strategy_result, { 'secret' => secret_params })
  end

  let(:max_length) do
    OT.conf.dig('site', 'secret_options', 'password_generation', 'maximum_length').to_i
  end

  context 'when the requested length exceeds the ceiling' do
    it 'raises a form error at construction, before strand ever allocates' do
      # Fail loudly if the guard is bypassed: strand must never be called with
      # an oversized length. process_params runs in the constructor, so the
      # guard fires during build_logic's `described_class.new` — that IS the
      # proof the rejection happens ahead of allocation.
      expect(Onetime::Utils).not_to receive(:strand)

      expect { build_logic('length' => '50000000', 'ttl' => '3600') }
        .to raise_error(OT::FormError, /no more than #{max_length} characters/)
    end
  end

  context 'when the payload attempts to raise the ceiling' do
    it 'is still rejected — the config ceiling wins over the payload' do
      # A caller who POSTs secret[maximum_length]=99999999 alongside an oversized
      # length must not be able to lift the guard: the ceiling is read from
      # config, not the merged payload.
      expect(Onetime::Utils).not_to receive(:strand)

      expect do
        build_logic(
          'length' => '1000',
          'maximum_length' => '99999999',
          'ttl' => '3600',
        )
      end.to raise_error(OT::FormError, /no more than #{max_length} characters/)
    end
  end

  context 'when the requested length is exactly at the ceiling' do
    it 'succeeds and produces a secret_value of ceiling size' do
      logic = build_logic('length' => max_length.to_s, 'ttl' => '3600')

      expect(logic.secret_value).to be_a(String)
      expect(logic.secret_value.length).to eq(max_length)
    end
  end

  context 'when the requested length is at or below the ceiling' do
    it 'succeeds and produces a secret_value of the requested size' do
      # build_logic runs process_params via the constructor.
      logic = build_logic('length' => '12', 'ttl' => '3600')

      expect(logic.secret_value).to be_a(String)
      expect(logic.secret_value.length).to eq(12)
    end
  end
end
