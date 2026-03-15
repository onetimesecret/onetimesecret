# These tryouts test the ShowSecretStatus and ListSecretStatus logic classes
# in the V2 API. They cover:
#
# 1. ShowSecretStatus: initialization, accessors, process, success_data for
#    missing/invalid/valid secret keys
# 2. ListSecretStatus: initialization, keys parsing, secrets accessor (the
#    recent bug fix), success_data for empty/invalid/valid keys

require_relative '../test_logic'

OT.boot! :test

@email = "tryouts+#{Time.now.to_i}@onetimesecret.com"
@cust = Customer.create @email

@created_objects = []

@create_secret = lambda {
  metadata = Metadata.create
  secret = Secret.create(value: "This is a secret message")
  metadata.secret_key = secret.key
  metadata.save
  @created_objects.push(metadata, secret)
  [metadata, secret]
}

class MockSession
  def authenticated?
    true
  end
  def add_shrimp
    "mock_shrimp"
  end
  def get_error_messages
    []
  end
  def get_info_messages
    []
  end
  def get_form_fields!
    {}
  end
  def event_incr!(event)
    "mock_event: #{event}"
  end
end

@sess = MockSession.new

# -- ShowSecretStatus --

## Can create a ShowSecretStatus logic with all arguments
params = {}
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
[logic.sess, logic.cust, logic.params, logic.locale]
#=> [@sess, @cust, {}, 'en']

## ShowSecretStatus has essential settings from base class
params = {}
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
[logic.site[:host], logic.authentication[:enabled], logic.domains_enabled]
#=> ["127.0.0.1:3000", true, false]

## ShowSecretStatus key is empty string when no key param provided
params = {}
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.key
#=> ""

## ShowSecretStatus secret is nil when key param is empty
params = {}
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.secret
#=> nil

## ShowSecretStatus secret is nil when key is invalid/nonexistent
params = { key: 'boguskey123' }
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.secret
#=> nil

## ShowSecretStatus success_data returns unknown state when secret is nil
params = {}
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.success_data
#=> { record: { state: 'unknown' } }

## ShowSecretStatus success_data returns unknown state for invalid key
params = { key: 'boguskey123' }
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.success_data
#=> { record: { state: 'unknown' } }

## ShowSecretStatus loads secret for valid key
metadata, secret = @create_secret.call
params = { key: secret.key }
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
[logic.secret.nil?, logic.key == params[:key]]
#=> [false, true]

## ShowSecretStatus realttl is nil before process is called
metadata, secret = @create_secret.call
params = { key: secret.key }
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.realttl
#=> nil

## ShowSecretStatus process sets realttl for a valid secret
metadata, secret = @create_secret.call
params = { key: secret.key }
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.raise_concerns
logic.process
logic.realttl.is_a?(Integer)
#=> true

## ShowSecretStatus success_data returns record and details for valid secret
metadata, secret = @create_secret.call
params = { key: secret.key }
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.raise_concerns
logic.process
ret = logic.success_data
ret.keys
#=> [:record, :details]

## ShowSecretStatus success_data record is a hash with expected keys
metadata, secret = @create_secret.call
params = { key: secret.key }
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.raise_concerns
logic.process
ret = logic.success_data
ret[:record].is_a?(Hash) && ret[:record].key?(:key) && ret[:record].key?(:state)
#=> true

## ShowSecretStatus success_data details contains realttl
metadata, secret = @create_secret.call
params = { key: secret.key }
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.raise_concerns
logic.process
ret = logic.success_data
ret[:details][:realttl].is_a?(Integer)
#=> true

## ShowSecretStatus process is safe when secret is nil
params = { key: 'bogus' }
logic = Logic::Secrets::ShowSecretStatus.new(@sess, @cust, params, 'en')
logic.process
logic.realttl
#=> nil

# -- ListSecretStatus --

## Can create a ListSecretStatus logic with all arguments
params = {}
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
[logic.sess, logic.cust, logic.params, logic.locale]
#=> [@sess, @cust, {}, 'en']

## ListSecretStatus keys accessor returns empty array when keys param is missing
params = {}
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
logic.keys
#=> []

## ListSecretStatus secrets accessor returns empty array when keys param is missing
params = {}
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
logic.secrets
#=> []

## ListSecretStatus success_data returns empty records when no keys
params = {}
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
logic.success_data
#=> { records: [], count: 0 }

## ListSecretStatus parses comma-separated keys
params = { keys: 'abc123,def456,ghi789' }
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
logic.keys
#=> ['abc123', 'def456', 'ghi789']

## ListSecretStatus strips whitespace and downcases keys
params = { keys: ' ABC123 , DEF456 ' }
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
logic.keys
#=> ['abc123', 'def456']

## ListSecretStatus strips non-alphanumeric characters (except commas) from keys
params = { keys: 'abc-123,def_456,ghi.789' }
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
logic.keys
#=> ['abc123', 'def456', 'ghi789']

## ListSecretStatus secrets is empty array for nonexistent keys
params = { keys: 'bogus1,bogus2,bogus3' }
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
logic.secrets
#=> []

## ListSecretStatus success_data returns count 0 for nonexistent keys
params = { keys: 'bogus1,bogus2' }
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
logic.success_data
#=> { records: [], count: 0 }

## ListSecretStatus returns safe_dump for valid secret keys
metadata, secret = @create_secret.call
params = { keys: secret.key }
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
ret = logic.success_data
[ret[:count], ret[:records].first.key?(:key)]
#=> [1, true]

## ListSecretStatus returns multiple records for multiple valid keys
metadata1, secret1 = @create_secret.call
metadata2, secret2 = @create_secret.call
params = { keys: "#{secret1.key},#{secret2.key}" }
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
ret = logic.success_data
ret[:count]
#=> 2

## ListSecretStatus filters out invalid keys and returns only valid ones
metadata, secret = @create_secret.call
params = { keys: "bogus1,#{secret.key},bogus2" }
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
ret = logic.success_data
ret[:count]
#=> 1

## ListSecretStatus process does not raise (noop body)
params = { keys: 'abc123' }
logic = Logic::Secrets::ListSecretStatus.new(@sess, @cust, params, 'en')
logic.raise_concerns
logic.process
true
#=> true

@created_objects.each { |obj| obj.destroy! rescue nil }
@cust.destroy!
