# try/unit/operations/sessions/track_metadata_try.rb
#
# frozen_string_literal: true

# Unit tryouts for the sidecar WRITE op (spec docs/specs/colonel-ui/40-*):
#   Onetime::Operations::Sessions::TrackMetadata
#
# Covers:
# - authenticated session_data -> upserts a SessionMetadata sidecar keyed by the
#   PLAIN sid AND indexes the sid into Customer#active_sessions (scored by
#   last_activity, adaptation #2)
# - ip/ua copied AS-IS (adaptation #3 — Otto masks upstream, no masking here)
# - anonymous session_data (no 'authenticated'/'external_id') is a NO-OP
# - an unresolvable customer is a NO-OP
# - BEST-EFFORT CONTRACT: an internal error after the guards pass is swallowed
#   (#call returns nil, no member leaks into the index)
#
# Run: try --agent try/unit/operations/sessions/track_metadata_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/sessions/track_metadata'

TM = Onetime::Operations::Sessions::TrackMetadata
SM = Onetime::SessionMetadata

@nonce = Familia.generate_id[0, 12]
@ts    = Familia.now.to_i

@cust  = Onetime::Customer.create!(email: "track_#{@nonce}@example.com")
@cust.verified = 'true'
@cust.save
@extid = @cust.extid

@sid = "trytrack_#{@nonce}"
SM.load(@sid)&.destroy!

@auth_session = {
  'authenticated' => true,
  'external_id'   => @extid,
  'email'         => @cust.email,
  'ip_address'    => '198.51.100.0',
  'user_agent'    => 'Firefox on Linux',
}

# ---- authenticated -> upsert + index ----------------------------------

## an authenticated session upserts a sidecar keyed by the plain sid
@meta = TM.new(session_id: @sid, session_data: @auth_session).call
[@meta.nil?, @meta.session_id, @meta.user_id]
#=> [false, "#{@sid}", "#{@extid}"]

## ip/ua are copied AS-IS (no masking in the op — adaptation #3)
@reload = SM.load(@sid)
[@reload.ip_address, @reload.user_agent]
#=> ["198.51.100.0", "Firefox on Linux"]

## the sid is indexed into the customer's active_sessions set
@cust.active_sessions.member?(@sid)
#=> true

## the index score is the last-activity epoch (>= this run's start)
@cust.active_sessions.score(@sid).to_i >= @ts
#=> true

## a re-track upserts (not duplicates): the set still holds ONE copy of the sid
@before_count = @cust.active_sessions.size
TM.new(session_id: @sid, session_data: @auth_session).call
[@cust.active_sessions.member?(@sid), @cust.active_sessions.size == @before_count]
#=> [true, true]

## created_at is preserved across re-track; last_activity_at is a live epoch
@r2 = SM.load(@sid)
[@r2.created_at.to_i >= @ts, @r2.last_activity_at.to_i >= @ts]
#=> [true, true]

# ---- anonymous / unresolvable -> no-op --------------------------------

## an anonymous session (no 'authenticated'/'external_id') is a no-op -> nil
@anon_sid = "tryanon_#{@nonce}"
SM.load(@anon_sid)&.destroy!
@r = TM.new(session_id: @anon_sid, session_data: { 'csrf' => "tok_#{@nonce}" }).call
[@r, SM.load(@anon_sid).nil?]
#=> [nil, true]

## an authenticated session whose customer cannot be resolved is a no-op -> nil
@ghost_sid = "tryghost_#{@nonce}"
SM.load(@ghost_sid)&.destroy!
@r = TM.new(session_id: @ghost_sid,
            session_data: { 'authenticated' => true, 'external_id' => "ur_missing_#{@nonce}" }).call
[@r, SM.load(@ghost_sid).nil?]
#=> [nil, true]

# ---- best-effort: internal error is swallowed -------------------------

## an error AFTER the guards pass is swallowed: #call returns nil and NOTHING
## lands in the index (stub restored in-body so later cases are unaffected)
@boom_sid = "tryboom_#{@nonce}"
SM.load(@boom_sid)&.destroy!
@cust.active_sessions.remove(@boom_sid)
klass = Onetime::Customer.singleton_class
orig  = Onetime::Customer.method(:find_by_extid)
klass.send(:define_method, :find_by_extid) { |_extid| raise 'boom: injected sidecar failure' }
begin
  @r = TM.new(session_id: @boom_sid, session_data: @auth_session).call
ensure
  klass.send(:define_method, :find_by_extid, orig)
end
[@r, @cust.active_sessions.member?(@boom_sid), SM.load(@boom_sid).nil?]
#=> [nil, false, true]

## the restore worked — a normal track succeeds again after the swallowed error
@ok = TM.new(session_id: @sid, session_data: @auth_session).call
@ok.nil?
#=> false

# ---- auth_method copied verbatim; org_id resolved from active org -----

## auth_method is copied verbatim from session_data (stamped once at auth time,
## NOT re-derived here). Any of password/email_auth/webauthn/omniauth flows.
@am_sid = "tryam_#{@nonce}"
SM.load(@am_sid)&.destroy!
@am = TM.new(session_id: @am_sid,
            session_data: @auth_session.merge('auth_method' => 'webauthn')).call
@am.auth_method
#=> "webauthn"

## org resolution is nil-safe: a customer with no organization writes the sidecar
## with org_id = nil, never raising (own rescue). (@cust has no org yet.)
@no_org_sid = "trynoorg_#{@nonce}"
SM.load(@no_org_sid)&.destroy!
@no = TM.new(session_id: @no_org_sid, session_data: @auth_session).call
[@no.nil?, @no.org_id.nil?]
#=> [false, true]

## org_id resolves to the customer's ACTIVE organization objid (via
## OrganizationLoader — read-through, so it populates even without a warmed cache)
@org     = Onetime::Organization.create!("Track Org #{@nonce}", @cust, "trackorg_#{@nonce}@example.com")
@org_sid = "tryorg_#{@nonce}"
SM.load(@org_sid)&.destroy!
@om = TM.new(session_id: @org_sid, session_data: @auth_session).call
@om.org_id == @org.objid
#=> true

# Cleanup
SM.load(@sid)&.destroy!
SM.load(@am_sid)&.destroy!
SM.load(@no_org_sid)&.destroy!
SM.load(@org_sid)&.destroy!
@org.destroy!
@cust.active_sessions.clear
@cust.destroy!
