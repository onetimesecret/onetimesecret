# tests/unit/ruby/try/30_session_try.rb

# These tryouts test the session management functionality in the Onetime application.
# They cover various aspects of session handling, including:
#
# 1. Session creation and initialization
# 2. Session identifiers and attributes
# 3. Form field management within sessions
# 4. Authentication status and auth disabling
# 5. Session reloading and replacement
#
# These tests aim to verify the correct behavior of the V2::Session class,
# which is crucial for maintaining user state and security in the application.
#
# The tryouts simulate different session scenarios and test the V2::Session class's
# behavior without needing to run the full application, allowing for targeted testing
# of these specific features.

require_relative '../helpers/test_models'
# Use the default config file for tests
OT.boot! :test, false

@ipaddress = '10.0.0.254' # A private IP address
@useragent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT 5.0)'
@custid = 'tryouts'

@sess = V2::Session.create @ipaddress, @custid, @useragent

## Sessions have a NIL session ID when _new_ is called
sess = V2::Session.new @ipaddress, @custid, @useragent
sess.instance_variable_get(:@sessid)
#=> nil

## Sessions have a session ID when _create_ is called
sessid = @sess.sessid
[sessid.class, (48..52).include?(sessid.length)]
#=> [String, true]

## Sessions have a unique session ID when _create_ is called the same arguments
@sess = V2::Session.create @ipaddress, @custid, @useragent
sess = V2::Session.create @ipaddress, @custid, @useragent
sessid1 = @sess.sessid
sessid2 = sess.sessid
[sessid1.eql?(sessid2), sessid1.eql?(''), sessid1.class, sessid2.class, sessid2.to_i(36).positive?, sessid2.to_i(36).positive?]
#=> [false, false, String, String, true, true]

## Sessions always have a ttl value
ttl = @sess.ttl
[ttl.class, ttl]
#=> [Float, 20.minutes]

## Sessions have an identifier
identifier = @sess.identifier
[identifier.class, (48..52).include?(identifier.length)]
#=> [String, true]

## Sessions have a short identifier
short_identifier = @sess.short_identifier
[short_identifier.class, short_identifier.length]
#=> [String, 12]

## Sessions have an IP address
ipaddress = @sess.ipaddress
[ipaddress.class, ipaddress]
#=> [String, @ipaddress]

## Sessions don't get unique IDs when instantiated
s1 = V2::Session.new '255.255.255.255', 'anon'
s2 = V2::Session.new '255.255.255.255', 'anon'
# Don't call s1.sessid by accessor method b/c that will generate one
s1.instance_variable_get(:@sessid).eql?(s2.instance_variable_get(:@sessid))
#=> true

## Can set form fields
ret = @sess.set_form_fields custid: 'tryouts', planid: :testing
ret.class
#=> Integer

## Can get form fields, with indifferent access via symbol or string
ret = @sess.get_form_fields!
[ret.class, ret[:custid], ret['custid']]
#=> [Hash, 'tryouts', 'tryouts']

## By default sessions do not have auth disabled
sess = V2::Session.create @ipaddress, @custid, @useragent
sess.disable_auth
#=> false

## Can set and get disable_auth
sess = V2::Session.create @ipaddress, @custid, @useragent
sess.disable_auth = true
sess.disable_auth
#=> true

## By default sessions are not authenticated
sess = V2::Session.create @ipaddress, @custid, @useragent
sess.authenticated?
#=> false

## Can set and check authenticated status
sess = V2::Session.create @ipaddress, @custid, @useragent
sess.authenticated = true
sess.authenticated?
#=> true

## Can force a session to be unauthenticated
@sess_disabled_auth = V2::Session.create @ipaddress, @custid, @useragent
@sess_disabled_auth.authenticated! true
@sess_disabled_auth.disable_auth = true
pp @sess_disabled_auth.to_h
@sess_disabled_auth.authenticated?
#=> false

## Load a new instance of the session and check authenticated status
sess = V2::Session.load @sess_disabled_auth.sessid
pp sess.to_h
[sess.authenticated?, sess.disable_auth]
#=> [true, false]

## Reload the same instance of the session and check authenticated status.
## Calling authenticated? will return false again b/c the instance var
## disable_auth is still set to true.
sess = @sess_disabled_auth.refresh
# NOTE: If you call refresh on an object that hasn't been saved yet or anytime
# that the key doesn't exist, it should raise an exception. Otherwise it will
# silently continue unchanged b/c there were no values to refresh. There might
# be a nuance between checking exists explicitly and assuming no key from an
# empty hgetall.
#
# See https://github.com/delano/familia/issues/36
#
pp sess.to_h
[sess.authenticated?, sess.disable_auth]
#=> [false, true]

## Replacing the session ID will update the session
@replaced_session = V2::Session.create @ipaddress, @custid, @useragent
initial_sessid = @replaced_session.sessid.to_s
@replaced_session.authenticated = true
@replaced_session.replace!
puts initial_sessid, @replaced_session.sessid
@replaced_session.sessid.eql?(initial_sessid)
#=> false

## Replaced session is stil authenticated
@replaced_session.authenticated?
#=> true

## Can check if a session exists
V2::Session.exists? @sess.sessid
#=> true

## Can load a session
sess = V2::Session.load @sess.sessid
sess.sessid.eql?(@sess.sessid)
#=> true

## Can generate a session ID
sid = V2::Session.generate_id
[sid.class, (48..52).include?(sid.length)]
#=> [String, true]

## Can update fields (1 of 2)
@sess_with_changes = V2::Session.create @ipaddress, @custid, @useragent
@sess_with_changes.apply_fields(custid: 'tryouts', stale: 'testing')
multi_result = @sess_with_changes.commit_fields
multi_result.tuple
#=> [true, ["OK"]]

## Can update fields (2 of 2)
[@sess_with_changes.custid, @sess_with_changes.stale]
#=> ["tryouts", "testing"]

## Can do the same thing but with save (1 of 2)
@sess_with_changes2 = V2::Session.create @ipaddress, @custid, @useragent
@sess_with_changes2.custid = 'tryouts2'
@sess_with_changes2.stale = 'testing2'
@sess_with_changes2.save
#=> true

## Can do the same thing but with save (2 of 2)
[@sess_with_changes2.custid, @sess_with_changes2.stale]
#=> ["tryouts2", "testing2"]

## Can call apply_fields and chain on commit_fields
multi_result = @sess_with_changes2.apply_fields(custid: 'tryouts3', stale: 'testing3').commit_fields
multi_result.tuple
#=> [true, ["OK"]]
