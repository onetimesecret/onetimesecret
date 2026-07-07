# try/unit/operations/ban_unban_ip_try.rb
#
# frozen_string_literal: true

#
# Unit tryouts for the extracted IP-ban operations (epic #33):
#   Onetime::Operations::BanIP / Onetime::Operations::UnbanIP
#
# These are the SINGLE implementation of the ban/unban verbs (the colonel API +
# `bin/ots bannedips` CLI are thin adapters). Covers:
# - BanIP: bans the IP, returns an immutable Result, records EXACTLY ONE audit
#   event (verb ip.ban, actor = PUBLIC id, target = ip), preserves banned_by
# - BanIP idempotency: an already-banned IP is a no-op (:already_banned, NO audit)
# - UnbanIP: removes the ban, returns :success, records exactly one audit event
# - UnbanIP not-found: unbanning a non-banned IP is a no-op (:not_found, NO audit)
# - Behavioural parity: the stored record matches a direct BannedIP.ban! call
#
# Run: try --agent try/unit/operations/ban_unban_ip_try.rb

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/operations/ban_ip'
require 'onetime/operations/unban_ip'

AE  = Onetime::AdminAuditEvent
BIP = Onetime::BannedIP

# Documentation-range IPs (RFC 5737 TEST-NET-3), unlikely to collide with fixtures.
@ip      = '203.0.113.201'
@ip_cidr = '198.51.100.0/24'
@actor   = 'ur1colonelpub' # a PUBLIC id (extid-shaped), never an objid
@stored  = 'objid_internal_colonel' # what the UI path stores in banned_by

# Clean slate.
BIP.unban!(@ip)
BIP.unban!(@ip_cidr)
AE.events.clear

# ---- BanIP: success ----------------------------------------------------

## BanIP returns a Result whose status is :success
@ban = Onetime::Operations::BanIP.new(
  ip_address: @ip, actor: @actor, reason: 'abuse', banned_by: @stored,
).call
@ban.status
#=> :success

## the ban Result carries the created record's public fields
[@ban.ip_address, @ban.reason, @ban.banned_by, @ban.id.is_a?(String)]
#=> ["203.0.113.201", "abuse", "objid_internal_colonel", true]

## the IP is now banned (model state actually mutated)
BIP.banned?(@ip)
#=> true

## exactly ONE audit event was recorded for the ban
AE.count
#=> 1

## the audit event is the ban verb, targeting the IP, actored by the PUBLIC id
@ev = AE.recent(1).first
[@ev['verb'], @ev['target'], @ev['actor']]
#=> ["ip.ban", "203.0.113.201", "ur1colonelpub"]

## the audit actor is the public id, never the stored objid
@ev['actor'].include?('objid_internal')
#=> false

## the audit detail carries the (non-secret) reason
@ev['detail']['reason']
#=> "abuse"

# ---- BanIP: idempotent no-op ------------------------------------------

## re-banning an already-banned IP is a no-op (:already_banned)
AE.events.clear
@rb = Onetime::Operations::BanIP.new(ip_address: @ip, actor: @actor).call
@rb.status
#=> :already_banned

## a no-op ban records NO audit event (nothing mutated)
AE.count
#=> 0

# ---- UnbanIP: success -------------------------------------------------

## UnbanIP removes the ban and returns :success
AE.events.clear
@unban = Onetime::Operations::UnbanIP.new(ip_address: @ip, actor: @actor).call
[@unban.status, @unban.unbanned]
#=> [:success, true]

## the IP is no longer banned
BIP.banned?(@ip)
#=> false

## exactly ONE audit event was recorded for the unban
AE.count
#=> 1

## the audit event is the unban verb targeting the IP
u = AE.recent(1).first
[u['verb'], u['target'], u['actor']]
#=> ["ip.unban", "203.0.113.201", "ur1colonelpub"]

# ---- UnbanIP: not-found no-op -----------------------------------------

## unbanning a non-banned IP is a no-op (:not_found)
AE.events.clear
@nf = Onetime::Operations::UnbanIP.new(ip_address: @ip, actor: @actor).call
[@nf.status, @nf.unbanned]
#=> [:not_found, false]

## a no-op unban records NO audit event
AE.count
#=> 0

# ---- Behavioural parity: CIDR ban + banned_by default -----------------

## a CIDR ban works and defaults banned_by to nil when not supplied
AE.events.clear
@cidr_ban = Onetime::Operations::BanIP.new(ip_address: @ip_cidr, actor: @actor).call
[@cidr_ban.status, @cidr_ban.banned_by.nil?]
#=> [:success, true]

## a CIDR ban covers addresses inside the range (CIDR matching preserved)
BIP.banned?('198.51.100.42')
#=> true

# Cleanup
BIP.unban!(@ip)
BIP.unban!(@ip_cidr)
AE.events.clear
