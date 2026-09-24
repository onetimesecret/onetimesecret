# apps/api/colonel/spec/logic/colonel/rate_limit_hook_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# The broad colonel:mutation charge (#4329), which lives in
# ColonelAPI::Logic::Base#initialize rather than in raise_concerns.
#
# WHY THE CONSTRUCTOR: none of the ~86 concrete colonel logic classes call
# `super` in raise_concerns, so a base-class hook there would be silently
# skipped, and covering 46 mutating verbs one file at a time is exactly the
# maintenance shape that leaves the 47th uncovered. By construction time Otto has
# already enforced role=colonel, so `cust` is the authenticated colonel — this is
# a budget charge on an authenticated request, not a pre-auth guard, and it is
# self-gated on has_system_role? so it can never charge an anonymous caller.
#
# What these examples own: WHICH requests are charged and with WHAT subject. The
# limiter body itself (key shapes, TTLs, the lockout, the audit write) is proven
# against real Redis in try/unit/security/colonel_rate_limiter_try.rb.
#
# The test subclass overrides `enforce_colonel_mutation_limit!` with a recorder,
# so these examples touch no datastore — the colonel unit suite runs without
# Redis and must keep doing so.
#
# RUN:
#   RACK_ENV=test bundle exec rspec \
#     apps/api/colonel/spec/logic/colonel/rate_limit_hook_spec.rb
RSpec.describe ColonelAPI::Logic::Base do
  let(:colonel) do
    instance_double(Onetime::Customer,
      objid: 'cust_colonel', extid: 'ur_colonel', email: 'colonel@example.com',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  let(:customer) do
    instance_double(Onetime::Customer,
      objid: 'cust_plain', extid: 'ur_plain',
      role: 'customer', verified?: true, anonymous?: false)
  end

  # Every subject the hook passed to the limiter, in call order.
  let(:charged) { [] }

  # A minimal concrete colonel logic class. Anonymous so it cannot drift with any
  # one endpoint's params, and so the examples describe the BASE contract rather
  # than one verb's.
  let(:logic_class) do
    log = charged
    Class.new(described_class) do
      define_method(:enforce_colonel_mutation_limit!) { |subject| log << subject }
      def process_params; end
    end
  end

  # `request_method` is what the colonel session auth strategy puts in the
  # strategy metadata (logic classes never see the Rack env). `:absent` means the
  # key was never merged — every pre-#4329 spec double, and any non-HTTP caller.
  def build(user: colonel, request_method: 'POST')
    metadata = { confirm_token: nil }
    metadata[:request_method] = request_method unless request_method == :absent

    logic_class.new(
      double('StrategyResult', session: {}, user: user, auth_method: 'sessionauth', metadata: metadata),
      {},
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
  end

  describe 'which requests are charged' do
    %w[POST PUT PATCH DELETE].each do |method|
      it "charges one unit for a #{method}" do
        build(request_method: method)
        expect(charged).to eq(['ur_colonel'])
      end
    end

    # The console fetches several reads on every screen; a limiter there would
    # break the dashboard. The two handle-resolving session reads are the one
    # exception and charge their OWN bucket, explicitly, in their own classes.
    %w[GET HEAD OPTIONS].each do |method|
      it "charges nothing for a #{method}" do
        build(request_method: method)
        expect(charged).to be_empty
      end
    end

    it 'is case-insensitive about the method' do
      build(request_method: 'delete')
      expect(charged).to eq(['ur_colonel'])
    end
  end

  describe 'who is charged' do
    it 'keys on the acting colonel PUBLIC extid, never an objid' do
      build
      expect(charged).to eq(['ur_colonel'])
      expect(charged).not_to include('cust_colonel')
    end

    # Otto rejects a non-colonel before a logic class is built, so this is a
    # belt-and-braces gate: the charge must never be reachable by an identity
    # the router would not have admitted, and must never mint a bucket for one.
    it 'charges nothing when the caller does not hold the colonel role' do
      build(user: customer)
      expect(charged).to be_empty
    end

    it 'charges nothing for an anonymous (nil) caller' do
      build(user: nil)
      expect(charged).to be_empty
    end

    # has_system_role? refuses every elevated role to an unverified account
    # (defence in depth, authorization_policies.rb).
    it 'charges nothing for an unverified colonel' do
      unverified = instance_double(Onetime::Customer,
        objid: 'cust_x', extid: 'ur_x', role: 'colonel', verified?: false, anonymous?: false)

      build(user: unverified)
      expect(charged).to be_empty
    end
  end

  describe 'metadata robustness' do
    # Every colonel spec written before #4329 builds a bare double whose metadata
    # carries no request_method. Reading that as "not a mutation" is the right
    # answer for a caller that did not come through the router, and it must not
    # raise.
    it 'charges nothing and does not raise when request_method is absent' do
      expect { build(request_method: :absent) }.not_to raise_error
      expect(charged).to be_empty
    end

    it 'charges nothing and does not raise when request_method is nil' do
      expect { build(request_method: nil) }.not_to raise_error
      expect(charged).to be_empty
    end
  end

  describe 'wiring' do
    it 'gives every colonel logic class the four limiter entry points' do
      expect(described_class.ancestors).to include(Onetime::Security::ColonelRateLimiter)
      expect(described_class.instance_methods).to include(
        :enforce_colonel_mutation_limit!,
        :enforce_colonel_destructive_limit!,
        :enforce_colonel_handle_resolve_limit!,
        :enforce_colonel_elevation_limit!,
      )
    end

    # The guard-order contract keeps the destructive charge as a SEPARATE call,
    # the last line of raise_concerns — never folded into the constructor hook.
    # A destructive verb therefore charges two buckets, which is intended.
    it 'does not charge the destructive bucket from the constructor' do
      instance = build
      expect(instance).to respond_to(:charge_destructive_budget!)
      expect(charged).to eq(['ur_colonel'])
    end
  end
end
