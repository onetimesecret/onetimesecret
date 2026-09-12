# try/unit/colonel/destructive_action_try.rb
#
# frozen_string_literal: true

# ColonelAPI::Logic::DestructiveAction — the shared guard concern introduced by
# #4326 and extended by the rest of epic #4323.
#
# What this file covers, at the level of the concern itself rather than any one
# verb (the per-class specs do that):
#
# 1. `truthy?` — the hoisted table. Ten colonel classes each had their own and
#    two of them disagreed (purge_dlq / replay_dlq accepted only %w[1 true yes]
#    and did not strip). This pins the widened, single form.
# 2. `supplied_confirmation` reads STRATEGY METADATA, never params — a `confirm`
#    query parameter must not be a back door, because the whole point of the
#    header transport is keeping target emails out of access logs and history.
# 3. The 255-char post-decode cap, and that whitespace is stripped.
# 4. `require_confirmation!` with a blank expected token raises
#    Onetime::GuardMisconfigured (500) rather than admitting the request.
# 5. `guard_destructive_action!` rejects an unknown tier — a typo'd tier would
#    otherwise silently drop elevation (#4327) and the tight bucket (#4329).
# 6. The rejection stays inside the Onetime::Forbidden family, which is what
#    keeps a hammered gate from minting audit events and flushing the
#    count-capped operator trail.
#
# Run: try --agent try/unit/colonel/destructive_action_try.rb

require_relative '../../support/test_models'
require 'colonel/logic'

OT.boot! :test

# A minimal host for the concern: a real colonel logic class needs a target to
# resolve, and none of that is what this file is about.
class TryDestructiveHost < ColonelAPI::Logic::Base
  def process_params; end
  def raise_concerns; end
end

def host_with(confirm_token)
  metadata = confirm_token.nil? ? {} : { confirm_token: confirm_token }
  TryDestructiveHost.new(
    MockStrategyResult.new(session: {}, user: nil, auth_method: 'sessionauth', metadata: metadata),
    {},
  )
end

@host = host_with('victim@example.com')

## truthy? accepts the whole widened table, case- and whitespace-insensitively
%W[true 1 yes on TRUE On \ yes\  #{"\ttrue\n"}].map { |v| @host.truthy?(v) }
#=> [true, true, true, true, true, true, true, true]

## truthy? rejects everything else, including nil and the falsy strings
[nil, '', 'false', '0', 'no', 'off', 'maybe', 'ontario'].map { |v| @host.truthy?(v) }
#=> [false, false, false, false, false, false, false, false]

## supplied_confirmation reads the strategy metadata
host_with('abc').supplied_confirmation
#=> "abc"

## supplied_confirmation is '' when no header was sent
host_with(nil).supplied_confirmation
#=> ""

## supplied_confirmation strips surrounding whitespace (headers pick it up)
host_with("  spaced@example.com \n").supplied_confirmation
#=> "spaced@example.com"

## supplied_confirmation caps at MAX_CONFIRM_LENGTH
host_with('z' * 1000).supplied_confirmation.length
#=> 255

## a `confirm` PARAM is NOT a fallback — the header is the only transport
TryDestructiveHost.new(
  MockStrategyResult.new(session: {}, user: nil, auth_method: 'sessionauth', metadata: {}),
  { 'confirm' => 'victim@example.com' },
).supplied_confirmation
#=> ""

## a non-ASCII token that survived percent-decoding compares equal
host_with('Acme Gmbh Überwachung').require_confirmation!(
  'Acme Gmbh Überwachung', subject: "the organization's name"
)
#=> true

## the exact token passes
@host.require_confirmation!('victim@example.com', subject: 'the account email address')
#=> true

## a wrong token is refused
begin
  @host.require_confirmation!('someone@else.example', subject: 'the account email address')
rescue Onetime::ConfirmationRequired => ex
  [ex.class.name, ex.to_h[:error_code], ex.is_a?(Onetime::Forbidden)]
end
#=> ["Onetime::ConfirmationRequired", "confirmation_required", true]

## a missing token is refused with the SAME message (no oracle)
missing = begin
  host_with(nil).require_confirmation!('victim@example.com', subject: 'the account email address')
rescue Onetime::ConfirmationRequired => ex
  ex.message
end
wrong = begin
  @host.require_confirmation!('someone@else.example', subject: 'the account email address')
rescue Onetime::ConfirmationRequired => ex
  ex.message
end
missing == wrong
#=> true

## the refusal message names the header and the subject, never the expected value
begin
  host_with(nil).require_confirmation!('victim@example.com', subject: 'the account email address')
  'no raise'
rescue Onetime::ConfirmationRequired => ex
  ex.message
end
#=> "Confirmation required: re-send this request with the X-OTS-Confirm header set to the account email address."

## the refusal carries the field the console should highlight
begin
  host_with(nil).require_confirmation!('x', subject: 's', field: :user_id)
rescue Onetime::ConfirmationRequired => ex
  ex.to_h[:field]
end
#=> :user_id

## a BLANK expected token is a 500, never a silent admit
begin
  @host.require_confirmation!('', subject: 'anything')
rescue Onetime::GuardMisconfigured => ex
  [ex.to_h[:error_type], ex.to_h[:error_code]]
end
#=> ["GuardMisconfigured", "guard_misconfigured"]

## a whitespace-only expected token is blank too
begin
  @host.require_confirmation!("  \n", subject: 'anything')
rescue Onetime::GuardMisconfigured
  :guarded
end
#=> :guarded

## guard_destructive_action! passes the confirmation through on a valid tier
@host.guard_destructive_action!(
  tier: :destructive, confirm_with: 'victim@example.com', confirm_subject: 'the email'
)
#=> true

## guard_destructive_action! refuses an unknown tier rather than downgrading
begin
  @host.guard_destructive_action!(
    tier: :mild, confirm_with: 'victim@example.com', confirm_subject: 'the email'
  )
rescue Onetime::GuardMisconfigured => ex
  ex.to_h[:error_code]
end
#=> "guard_misconfigured"

## account_confirm_token prefers the email
@host.account_confirm_token(Struct.new(:email, :extid).new('a@b.example', 'ur_x'))
#=> "a@b.example"

## account_confirm_token falls back to the extid when there is no email
@host.account_confirm_token(Struct.new(:email, :extid).new('  ', 'ur_x'))
#=> "ur_x"

## org_confirm_token prefers the display name, falls back to the extid
org = Struct.new(:display_name, :extid)
[@host.org_confirm_token(org.new('Acme', 'or_x')), @host.org_confirm_token(org.new('', 'or_x'))]
#=> ["Acme", "or_x"]

## every colonel logic class HAS the guards (they are on the shared Base)
ColonelAPI::Logic::Colonel::PurgeUser.method_defined?(:guard_destructive_action!)
#=> true

## charge_destructive_budget! is a declared no-op until #4329 fills it in
@host.charge_destructive_budget!
#=> nil
