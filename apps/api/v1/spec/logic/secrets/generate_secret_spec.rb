# apps/api/v1/spec/logic/secrets/generate_secret_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Regression coverage for the C5 generate-length DoS on the legacy V1 endpoint
# (POST /api/v1/generate).
#
# V1 reads `payload['length']` directly (no merged 'secret' namespace). The
# allocating call `Onetime::Utils.strand(length, ...)` runs inside
# process_secret, which fires from process_params in the LOGIC CONSTRUCTOR
# (apps/api/v1/logic/base.rb:38) — so the ceiling must be enforced in
# process_secret, immediately before strand, or the oversized string is already
# allocated. The cap is read from CONFIG, not the payload, so a caller cannot
# lift the guard by sending a large `length`.
RSpec.describe V1::Logic::Secrets::GenerateSecret do
  let(:session)  { double('Session') }
  let(:customer) { double('Onetime::Customer', anonymous?: true, custid: 'anon') }

  before(:all) do
    OT.boot!(:test)
  end

  let(:max_length) do
    OT.conf.dig('site', 'secret_options', 'password_generation', 'maximum_length').to_i
  end

  context 'when the requested length exceeds the ceiling' do
    it 'raises a form error at construction, before strand ever allocates' do
      # V1 runs process_params (hence process_secret) in the constructor, so the
      # guard fires during `described_class.new` — that IS the proof the
      # rejection happens ahead of allocation. strand must never be reached.
      expect(Onetime::Utils).not_to receive(:strand)

      expect { described_class.new(session, customer, 'length' => '50000000') }
        .to raise_error(OT::FormError, /no more than #{max_length} characters/)
    end
  end

  context 'when the payload sends an oversized length to override the ceiling' do
    it 'is still rejected — the config ceiling wins over the payload' do
      # V1 has no merged config/payload hash; the ceiling comes from config, so a
      # caller sending a huge `length` cannot raise it. length=99999999 is rejected.
      expect(Onetime::Utils).not_to receive(:strand)

      expect { described_class.new(session, customer, 'length' => '99999999') }
        .to raise_error(OT::FormError, /no more than #{max_length} characters/)
    end
  end

  context 'when the requested length is exactly at the ceiling' do
    it 'succeeds and produces a secret_value of ceiling size' do
      logic = described_class.new(session, customer, 'length' => max_length.to_s)

      expect(logic.secret_value).to be_a(String)
      expect(logic.secret_value.length).to eq(max_length)
    end
  end

  context 'when the requested length is at or below the ceiling' do
    it 'succeeds and produces a secret_value of the requested size' do
      logic = described_class.new(session, customer, 'length' => '12')

      expect(logic.secret_value).to be_a(String)
      expect(logic.secret_value.length).to eq(12)
    end
  end
end
