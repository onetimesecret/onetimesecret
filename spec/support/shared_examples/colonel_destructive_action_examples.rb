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

# The step-up (sudo) window (#4327) — the contract every TIER 1 colonel logic
# class shares, on top of the confirmation contract above.
#
# The host spec supplies one method (and inherits `expected_confirm_token` from
# the confirmation examples):
#
#   def elevated_logic_for(session, confirm_token = expected_confirm_token)
#     described_class.new(strategy_result_for(colonel, confirm_token, session), params)
#   end
#
# `session` is the Rack session hash the strategy hands the logic class — the
# same place ColonelAPI::Logic::Colonel::Elevation reads and writes
# `elevated_until`. Build a live one with {ColonelElevationHelpers#elevated_session}.
#
# `acting_extid` defaults to the host's `colonel` double's public id; override it
# only if the host names its acting colonel something else.
#
# Elevation is DISABLED in spec/config.test.yaml, so these examples turn it on
# in-process — which also means the confirmation examples above keep exercising
# the un-elevated path, exactly as they did before #4327.
RSpec.shared_examples 'an elevated colonel action' do
  let(:acting_extid) { colonel.extid }

  before do
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_security)
    stub_colonel_elevation(enabled: true, window: 600)
  end

  it 'refuses when the session holds no elevation record' do
    expect { elevated_logic_for({}).raise_concerns }.to raise_error(Onetime::ElevationRequired)
  end

  it 'refuses an expired window' do
    session = elevated_session(acting_extid, expires_in: -1)
    expect { elevated_logic_for(session).raise_concerns }.to raise_error(Onetime::ElevationRequired)
  end

  # B-2: one onetime.session cookie can outlive an identity change, so a record
  # naming a different account must never be honoured.
  it 'ignores a window minted by a different identity' do
    session = elevated_session('ur_someone_else')
    expect { elevated_logic_for(session).raise_concerns }.to raise_error(Onetime::ElevationRequired)
  end

  it 'ignores a bare-epoch value (the shape an earlier draft would have stored)' do
    session = { 'elevated_until' => Familia.now.to_i + 600 }
    expect { elevated_logic_for(session).raise_concerns }.to raise_error(Onetime::ElevationRequired)
  end

  it 'ignores an unparseable value' do
    session = { 'elevated_until' => '{not json' }
    expect { elevated_logic_for(session).raise_concerns }.to raise_error(Onetime::ElevationRequired)
  end

  it 'accepts a live, identity-matched window' do
    session = elevated_session(acting_extid)
    expect { elevated_logic_for(session).raise_concerns }.not_to raise_error
  end

  # Guard order §0.2 step 3: elevation BEFORE confirmation. An unelevated caller
  # must never learn whether their confirmation-token guess was right.
  it 'answers the elevation refusal, not the confirmation refusal, when both apply' do
    expect { elevated_logic_for({}, 'not-the-token').raise_concerns }
      .to raise_error(Onetime::ElevationRequired)
  end

  it 'answers 403 Forbidden with error_code elevation_required and the window' do
    error = begin
      elevated_logic_for({}).raise_concerns
    rescue Onetime::ElevationRequired => ex
      ex
    end

    expect(error).to be_a(Onetime::Forbidden)
    expect(error.to_h).to include(
      error_type: 'ElevationRequired',
      error_code: 'elevation_required',
      window: 600,
    )
  end

  # Same reason as the confirmation gate: a cookie holder can drive this
  # rejection on demand, and the operator trail is count-capped with no TTL.
  it 'writes NO audit event when elevation is refused' do
    expect { elevated_logic_for({}).raise_concerns }.to raise_error(Onetime::ElevationRequired)
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    expect(Onetime::ColonelAuditEvent).not_to have_received(:record_security)
  end

  it 'is a no-op when elevation is disabled by config' do
    stub_colonel_elevation(enabled: false)
    expect { elevated_logic_for({}).raise_concerns }.not_to raise_error
  end
end
