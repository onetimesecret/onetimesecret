# spec/support/shared_examples/colonel_destructive_action_examples.rb
#
# frozen_string_literal: true

# Server-side destructive-action confirmation (#4326) — the contract every gated
# colonel logic class shares.
#
# The host spec supplies two things:
#
#   let(:expected_confirm_token) { 'victim@example.com' }
#
#   def confirmed_logic_for(confirm_token)
#     described_class.new(strategy_result_for(colonel, confirm_token), params)
#   end
#
# `confirm_token` reaches the logic class through StrategyResult#metadata
# (`{ confirm_token: … }`) because that is where the colonel session auth
# strategy puts the percent-decoded `X-OTS-Confirm` header — never params. Pass
# nil for "no header sent".
#
# Rejections must stay in the Onetime::Forbidden family: AuditedFailure drops
# that family, so a compromised colonel session cannot mint audit events by
# hammering the gate and flush the count-capped operator trail.
RSpec.shared_examples 'a confirmed colonel action' do
  # Stubbed here rather than assumed of the host spec: the "no event on a
  # rejection" assertion is the point, and a host that never audits at all has
  # no reason to have stubbed the sink.
  before { allow(Onetime::ColonelAuditEvent).to receive(:record) }

  it 'refuses when no confirmation header was sent' do
    logic = confirmed_logic_for(nil)
    expect { logic.raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
  end

  it 'refuses a wrong token with the identical message (no oracle on which half was wrong)' do
    missing = begin
      confirmed_logic_for(nil).raise_concerns
    rescue Onetime::ConfirmationRequired => ex
      ex
    end
    wrong = begin
      confirmed_logic_for('not-the-token').raise_concerns
    rescue Onetime::ConfirmationRequired => ex
      ex
    end

    expect(wrong.message).to eq(missing.message)
  end

  it 'refuses a prefix of the expected token' do
    logic = confirmed_logic_for(expected_confirm_token[0..-2])
    expect { logic.raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
  end

  it 'accepts the exact token' do
    logic = confirmed_logic_for(expected_confirm_token)
    expect { logic.raise_concerns }.not_to raise_error
  end

  it 'tolerates surrounding whitespace on the supplied token' do
    logic = confirmed_logic_for("  #{expected_confirm_token}\n")
    expect { logic.raise_concerns }.not_to raise_error
  end

  it 'answers 403 Forbidden with error_code confirmation_required' do
    logic = confirmed_logic_for(nil)
    error = begin
      logic.raise_concerns
    rescue Onetime::ConfirmationRequired => ex
      ex
    end

    expect(error).to be_a(Onetime::Forbidden)
    expect(error.to_h).to include(
      error_type: 'ConfirmationRequired',
      error_code: 'confirmation_required',
    )
  end

  it 'writes NO audit event when the confirmation is missing or wrong' do
    expect { confirmed_logic_for(nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
    expect { confirmed_logic_for('nope').raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
  end
end
