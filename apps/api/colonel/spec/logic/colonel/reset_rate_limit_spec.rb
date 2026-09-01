# apps/api/colonel/spec/logic/colonel/reset_rate_limit_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# POST /api/colonel/ratelimit/reset — removes an active defence, so TIER 2
# (#4326). The op owns the delete and the single ColonelAuditEvent.
#
# The confirmation token is COMPOSED: "<kind>:<subject>". That composition is
# only safe because the two required-field guards run first — an empty kind and
# subject would compose the non-blank string ":" and slip past the
# blank-expected tripwire in require_confirmation!. The unreachability of that
# case is asserted here explicitly, because it is a property of the ORDER of two
# statements and nothing else would catch a reordering.
RSpec.describe ColonelAPI::Logic::Colonel::ResetRateLimit do
  let(:kind) { Onetime::Operations::RateLimit::Registry::LIMITERS.keys.first }
  let(:subject_id) { 'ur_target' }

  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_plain', extid: 'ur_plain',
      role: 'customer', verified?: true, anonymous?: false)
  end

  let(:op) do
    instance_double(
      Onetime::Operations::RateLimit::Reset,
      call: Onetime::Operations::RateLimit::Reset::Result.new(
        status: :success, kind: kind, subject: subject_id, keys: ['k'], deleted: 1,
      ),
    )
  end

  # `confirm_token` is where the colonel session auth strategy puts the
  # percent-decoded X-OTS-Confirm header — never params.
  def strategy_result_for(user, confirm_token)
    double('StrategyResult', session: {}, user: user,
      auth_method: 'sessionauth', metadata: { confirm_token: confirm_token })
  end

  def logic_for(user = colonel, confirm_token = nil, params = {})
    described_class.new(
      strategy_result_for(user, confirm_token || "#{kind}:#{subject_id}"),
      { 'kind' => kind, 'subject' => subject_id }.merge(params),
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(Onetime::Operations::RateLimit::Reset).to receive(:new).and_return(op)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  describe 'confirmation (#4326)' do
    let(:expected_confirm_token) { "#{kind}:#{subject_id}" }

    def confirmed_logic_for(confirm_token)
      described_class.new(
        strategy_result_for(colonel, confirm_token),
        { 'kind' => kind, 'subject' => subject_id },
      )
    end

    it_behaves_like 'a confirmed colonel action'

    it 'does not accept either half on its own' do
      expect { confirmed_logic_for(kind).raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
      expect { confirmed_logic_for(subject_id).raise_concerns }
        .to raise_error(Onetime::ConfirmationRequired)
    end

    it 'resets nothing when the confirmation is refused' do
      expect { confirmed_logic_for(nil).raise_concerns }.to raise_error(Onetime::ConfirmationRequired)
      expect(Onetime::Operations::RateLimit::Reset).not_to have_received(:new)
    end
  end

  describe 'the composed token can never be a bare ":"' do
    # Both halves are required BEFORE the guard runs, so `":"` — which is
    # non-blank and would therefore pass the guard's blank-expected tripwire —
    # is unreachable. These two examples are what keeps that ordering honest.
    it 'refuses a blank kind with a 422, before the guard' do
      expect { logic_for(colonel, ':', 'kind' => '').raise_concerns }
        .to raise_error(Onetime::FormError, /Limiter kind is required/)
    end

    it 'refuses a blank subject with a 422, before the guard' do
      expect { logic_for(colonel, ':', 'subject' => '').raise_concerns }
        .to raise_error(Onetime::FormError, /Subject is required/)
    end
  end

  describe 'guard order (§0.2)' do
    it 'rejects an unknown limiter kind BEFORE the confirmation gate' do
      expect { logic_for(colonel, 'nope:ur_target', 'kind' => 'not-a-limiter').raise_concerns }
        .to raise_error(Onetime::RecordNotFound, /Unknown rate limiter/)
    end

    it 'rejects a non-colonel before either' do
      expect { logic_for(customer).raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  describe 'the happy path still works' do
    it 'hands the op the kind, subject and the acting colonel extid' do
      logic = logic_for
      logic.raise_concerns
      data = logic.process

      expect(Onetime::Operations::RateLimit::Reset).to have_received(:new)
        .with(hash_including(kind: kind, subject: subject_id, actor: 'ur_colonel'))
      expect(data[:record][:cleared]).to be true
    end
  end
end
