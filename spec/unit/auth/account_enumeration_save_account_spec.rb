# spec/unit/auth/account_enumeration_save_account_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'rodauth'

# Namespace shim (see memory: production apps/web/auth/config.rb defines
# `class Config < Rodauth::Auth` and test files must NOT require it — the
# shim must be a Rodauth::Auth SUBCLASS so a later real reopen is
# superclass-compatible in either load order).
require 'auth/lib/logging'
Auth.const_set(:Config, Class.new(Rodauth::Auth)) unless defined?(Auth::Config)

require 'auth/config/overrides/account_enumeration'

# Pins the M-2 race-window cover in RouteScopedGuards#save_account (PR #3972
# review finding): Rodauth 2.44.0's save_account traps a duplicate-INSERT
# uniqueness violation internally and returns FALSY — an implementation
# detail, not interface. If a future Rodauth raises
# Sequel::UniqueConstraintViolation instead, the override must route that
# raise through the SAME generic duplicate-signup success (never a 500), and
# only on the HTTP create-account route. Both duplicate signals are pinned
# here against a stubbed `super` so the cover cannot silently become dead
# code when Rodauth changes semantics.
RSpec.describe 'AccountEnumeration::RouteScopedGuards#save_account' do
  let(:guards) { Auth::Config::Overrides::AccountEnumeration::RouteScopedGuards }

  # Fake Rodauth base: `super` for the prepended module. Simulates the two
  # duplicate signals (falsy return / raise) plus the success path.
  let(:base_class) do
    Class.new do
      attr_accessor :route, :super_result, :super_raises

      def save_account
        raise Sequel::UniqueConstraintViolation, 'duplicate key value violates unique constraint' if super_raises

        super_result
      end

      def current_route
        route
      end

      def login_param
        'login'
      end

      def param(_key)
        'race-loser@example.com'
      end
    end
  end

  let(:harness_class) do
    klass = Class.new(base_class)
    klass.prepend(guards)
    # Stub the halting response ABOVE RouteScopedGuards in the ancestry (last
    # prepend is consulted first) so the spec observes the halt contract —
    # the real duplicate_signup_success_response halts via
    # create_account_response's request.halt, i.e. a `throw`, which a rescue
    # cannot swallow — without standing up the full Rodauth response stack.
    klass.prepend(Module.new do
      def duplicate_signup_success_response(_existing_account: nil)
        throw :halt, :generic_duplicate_success
      end
    end)
    klass
  end

  let(:auth) { harness_class.new }

  before do
    allow(Auth::Logging).to receive(:log_auth_event)
  end

  describe 'on the create-account route' do
    before { auth.route = :create_account }

    it 'covers raise-on-conflict semantics: halts with the generic success, no error escapes' do
      auth.super_raises = true

      result = catch(:halt) { auth.save_account }

      expect(result).to eq(:generic_duplicate_success)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:registration_duplicate_insert_race, hash_including(level: :info))
    end

    it 'covers falsy-return semantics (stock 2.44.0): halts with the same generic success' do
      auth.super_result = nil

      result = catch(:halt) { auth.save_account }

      expect(result).to eq(:generic_duplicate_success)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:registration_duplicate_insert_race, hash_including(level: :info))
    end

    it 'passes a successful insert through untouched (returns the id, no halt, no log)' do
      auth.super_result = 42

      expect(auth.save_account).to eq(42)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
    end
  end

  describe 'off the create-account route (internal_request has current_route nil)' do
    it 're-raises a uniqueness violation unchanged' do
      auth.route        = nil
      auth.super_raises = true

      expect { auth.save_account }.to raise_error(Sequel::UniqueConstraintViolation)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
    end

    it 'passes a falsy return through without the generic-success response' do
      auth.route        = :some_other_route
      auth.super_result = false

      expect { expect(auth.save_account).to be(false) }.not_to throw_symbol(:halt)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
    end
  end

  # PR #3972 review finding B: the dummy login-timing hash is memoized once
  # per process on the MODULE, not on Auth::Config.configured — a spec that
  # re-runs configure under a changed env must be able to reset it.
  describe '.reset_dummy_password_hash!' do
    let(:mod) { Auth::Config::Overrides::AccountEnumeration }

    it 'clears the per-process memoized hash so configure can rebuild it' do
      original = mod.dummy_password_hash
      mod.instance_variable_set(:@dummy_password_hash, 'stale-hash')

      expect { mod.reset_dummy_password_hash! }
        .to change(mod, :dummy_password_hash).from('stale-hash').to(nil)
    ensure
      mod.instance_variable_set(:@dummy_password_hash, original)
    end
  end
end
