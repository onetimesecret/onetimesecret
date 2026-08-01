# try/unit/models/custom_domain_config_boolean_encoding_try.rb
#
# frozen_string_literal: true

# Matrix tests for the boolean_encoding feature (#3951) across ALL SEVEN
# CustomDomain config models and every FIELD_SPECS boolean field.
#
# Background: the seven config models historically disagreed on boolean
# persistence — some fields store REAL booleans (storage :native), others
# store 'true'/'false' STRINGS (storage :string). Writers that bypass
# ConfigRegistry.apply_field (console, create!/upsert) could persist the
# "wrong" encoding, and the old strict `== true` predicates then silently
# read the record as disabled. The boolean_encoding feature makes every
# declared boolean field tolerant on READ and normalizing on WRITE.
#
# Covers, for each spec'd boolean field:
#   - Assigning each of true, 'true', 1, '1' reads true through the predicate
#     AND persists in the model's DECLARED storage encoding. Raw hash bytes
#     verified via Familia.dbclient.hget(obj.dbkey, field):
#       :native  -> unquoted 'true'  (Familia JSON round-trip of boolean)
#       :string  -> '"true"'         (JSON-quoted string)
#   - Assigning each of false, 'false', 0, '0' reads false and persists the
#     encoded false the same way
#   - nil passes through the setter unchanged (nil means unset, never coerced)
#   - LEGACY/opposite-encoding persisted records (raw hset of 'true' and
#     '"true"') read as enabled after reload, on one :native model
#     (SigninConfig) and one :string model (SsoConfig)
#   - A typo'd/renamed boolean field in FIELD_SPECS raises at
#     feature-enable (load) time, since the generated accessors would
#     otherwise satisfy ConfigRegistry's method_defined? transcription check
#
# Field/storage map under test (single source of truth is each model's
# FIELD_SPECS):
#   SigninConfig   enabled, signin_enabled, email_auth_enabled, sso_enabled  :native
#   SignupConfig   enabled :string; signup_enabled, autoverify :native (MIXED)
#   HomepageConfig enabled :string
#   ApiConfig      enabled :string
#   IncomingConfig enabled :string
#   SsoConfig      enabled, enforce_sso_only, grant_org_scope :string
#   MailerConfig   enabled :string (tri-state dns_verified/provider_verified
#                  are deliberately NOT spec'd and NOT covered here)
#
# Run:
#   try try/unit/models/custom_domain_config_boolean_encoding_try.rb --agent

require_relative '../../support/test_models'

OT.boot! :test

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for config boolean encoding matrix test run'

TRUTHY_INPUTS = [true, 'true', 1, '1'].freeze
FALSY_INPUTS  = [false, 'false', 0, '0'].freeze

# Assign each input to each field, save, then read back the predicate AND the
# raw stored hash bytes. Returns the uniq [predicate, raw] pairs — a
# single-element result proves every input converged on ONE read result and
# ONE stored encoding.
def boolean_matrix(obj, fields, inputs)
  Array(fields).flat_map do |field|
    inputs.map do |input|
      obj.send(:"#{field}=", input)
      obj.save
      [obj.send(:"#{field}?"), Familia.dbclient.hget(obj.dbkey, field.to_s)]
    end
  end.uniq
end

# nil must pass through the setter unchanged (nil means unset — the feature
# never coerces it to an encoded false). Returns uniq
# [value_is_nil, predicate] pairs; expect [[true, false]].
def nil_passthrough(obj, fields)
  Array(fields).map do |field|
    obj.send(:"#{field}=", true) # prove nil actually overwrites a set value
    obj.send(:"#{field}=", nil)
    [obj.send(field).nil?, obj.send(:"#{field}?")]
  end.uniq
end

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner   = Onetime::Customer.create!(email: "be_owner_#{@ts}_#{@entropy}@test.com")
@org     = Onetime::Organization.create!("BE Test Org #{@ts}", @owner, "be_#{@ts}@test.com")

# CustomDomain.create! bootstraps HomepageConfig + ApiConfig (disabled); the
# other five kinds are created explicitly against the same domain.
@domain = Onetime::CustomDomain.create!("be-matrix-#{@ts}-#{@entropy}.example.com", @org.objid)
@did    = @domain.identifier

@signin   = Onetime::CustomDomain::SigninConfig.create!(domain_id: @did)
@signup   = Onetime::CustomDomain::SignupConfig.create!(domain_id: @did, validation_strategy: 'passthrough')
@homepage = Onetime::CustomDomain::HomepageConfig.find_by_domain_id(@did)
@api      = Onetime::CustomDomain::ApiConfig.find_by_domain_id(@did)
@incoming = Onetime::CustomDomain::IncomingConfig.create!(domain_id: @did)
@mailer   = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @did,
  provider: 'ses',
  from_address: "noreply@be-matrix-#{@ts}.example.com",
)
# SsoConfig.create! validates credentials (encrypted fields); the boolean
# machinery needs neither, so build via new + save.
@sso      = Onetime::CustomDomain::SsoConfig.new(domain_id: @did)
@sso.save

# --- SigninConfig: four :native boolean fields ---

## SigninConfig truthy matrix: true/'true'/1/'1' all read true and store the
## native (unquoted) boolean encoding on every spec'd field
boolean_matrix(@signin, %w[enabled signin_enabled email_auth_enabled sso_enabled], TRUTHY_INPUTS)
#=> [[true, 'true']]

## SigninConfig falsy matrix: false/'false'/0/'0' all read false, stored native
boolean_matrix(@signin, %w[enabled signin_enabled email_auth_enabled sso_enabled], FALSY_INPUTS)
#=> [[false, 'false']]

## SigninConfig nil passthrough: setter never coerces nil; predicate reads false
nil_passthrough(@signin, %w[enabled signin_enabled email_auth_enabled sso_enabled])
#=> [[true, false]]

# --- SignupConfig: MIXED encoding (enabled :string; the rest :native) ---

## SignupConfig enabled (:string) truthy matrix: stores JSON-quoted '"true"'
boolean_matrix(@signup, %w[enabled], TRUTHY_INPUTS)
#=> [[true, '"true"']]

## SignupConfig enabled (:string) falsy matrix: stores JSON-quoted '"false"'
boolean_matrix(@signup, %w[enabled], FALSY_INPUTS)
#=> [[false, '"false"']]

## SignupConfig signup_enabled/autoverify (:native) truthy matrix: store
## unquoted booleans even when assigned strings — normalized on write
boolean_matrix(@signup, %w[signup_enabled autoverify], TRUTHY_INPUTS)
#=> [[true, 'true']]

## SignupConfig signup_enabled/autoverify (:native) falsy matrix
boolean_matrix(@signup, %w[signup_enabled autoverify], FALSY_INPUTS)
#=> [[false, 'false']]

## SignupConfig nil passthrough across all three boolean fields
nil_passthrough(@signup, %w[enabled signup_enabled autoverify])
#=> [[true, false]]

# --- HomepageConfig: enabled :string ---

## HomepageConfig enabled truthy matrix: stores '"true"'
boolean_matrix(@homepage, %w[enabled], TRUTHY_INPUTS)
#=> [[true, '"true"']]

## HomepageConfig enabled falsy matrix: stores '"false"'
boolean_matrix(@homepage, %w[enabled], FALSY_INPUTS)
#=> [[false, '"false"']]

## HomepageConfig nil passthrough
nil_passthrough(@homepage, %w[enabled])
#=> [[true, false]]

# --- ApiConfig: enabled :string ---

## ApiConfig enabled truthy matrix: stores '"true"'
boolean_matrix(@api, %w[enabled], TRUTHY_INPUTS)
#=> [[true, '"true"']]

## ApiConfig enabled falsy matrix: stores '"false"'
boolean_matrix(@api, %w[enabled], FALSY_INPUTS)
#=> [[false, '"false"']]

## ApiConfig nil passthrough
nil_passthrough(@api, %w[enabled])
#=> [[true, false]]

# --- IncomingConfig: enabled :string ---

## IncomingConfig enabled truthy matrix: stores '"true"'
boolean_matrix(@incoming, %w[enabled], TRUTHY_INPUTS)
#=> [[true, '"true"']]

## IncomingConfig enabled falsy matrix: stores '"false"'
boolean_matrix(@incoming, %w[enabled], FALSY_INPUTS)
#=> [[false, '"false"']]

## IncomingConfig nil passthrough
nil_passthrough(@incoming, %w[enabled])
#=> [[true, false]]

# --- SsoConfig: three :string boolean fields ---

## SsoConfig truthy matrix: real boolean or 1/'1' assignments normalize to the
## string encoding — 'cfg.enabled = true' persists '"true"', not raw 'true'
boolean_matrix(@sso, %w[enabled enforce_sso_only grant_org_scope], TRUTHY_INPUTS)
#=> [[true, '"true"']]

## SsoConfig falsy matrix: stores '"false"'
boolean_matrix(@sso, %w[enabled enforce_sso_only grant_org_scope], FALSY_INPUTS)
#=> [[false, '"false"']]

## SsoConfig nil passthrough
nil_passthrough(@sso, %w[enabled enforce_sso_only grant_org_scope])
#=> [[true, false]]

# --- MailerConfig: enabled :string (tri-state fields NOT covered — see header) ---

## MailerConfig enabled truthy matrix: stores '"true"'
boolean_matrix(@mailer, %w[enabled], TRUTHY_INPUTS)
#=> [[true, '"true"']]

## MailerConfig enabled falsy matrix: stores '"false"'
boolean_matrix(@mailer, %w[enabled], FALSY_INPUTS)
#=> [[false, '"false"']]

## MailerConfig nil passthrough
nil_passthrough(@mailer, %w[enabled])
#=> [[true, false]]

# --- Legacy / opposite-encoding persisted records (READ tolerance) ---
# Simulate rows written by pre-#3951 code or by writers that bypass the
# setters entirely (fast writers, direct Redis writes) by hset-ing raw bytes:
#   raw 'true'   -> Familia JSON round-trip loads a real BOOLEAN
#   raw '"true"' -> loads the STRING 'true'
# Both must read enabled through the predicate after a reload, regardless of
# the field's declared storage.

## Legacy on :native model (SigninConfig): raw unquoted 'true' loads as a
## boolean and reads enabled
@legacy_dom_n = Onetime::CustomDomain.create!("be-legacy-n-#{@ts}-#{@entropy}.example.com", @org.objid)
@legacy_si    = Onetime::CustomDomain::SigninConfig.create!(domain_id: @legacy_dom_n.identifier)
Familia.dbclient.hset(@legacy_si.dbkey, 'enabled', 'true')
Onetime::CustomDomain::SigninConfig.find_by_domain_id(@legacy_dom_n.identifier).enabled?
#=> true

## Legacy on :native model (SigninConfig): quoted '"true"' — the OPPOSITE
## (string) encoding for a native field — still reads enabled. Pre-#3951 the
## strict `== true` predicate read this record as silently disabled.
Familia.dbclient.hset(@legacy_si.dbkey, 'signin_enabled', '"true"')
@legacy_si_loaded = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@legacy_dom_n.identifier)
@legacy_si_loaded.signin_enabled?
#=> true

## Loading routes through the normalizing setter, so the IN-MEMORY value for
## the quoted-string row is already a real boolean (stored bytes untouched
## until something saves the record)
[@legacy_si_loaded.signin_enabled, Familia.dbclient.hget(@legacy_si.dbkey, 'signin_enabled')]
#=> [true, '"true"']

## Legacy on :string model (SsoConfig): raw unquoted 'true' — the OPPOSITE
## (boolean) encoding for a string field — loads as a boolean and reads enabled
@legacy_dom_s = Onetime::CustomDomain.create!("be-legacy-s-#{@ts}-#{@entropy}.example.com", @org.objid)
@legacy_sso   = Onetime::CustomDomain::SsoConfig.new(domain_id: @legacy_dom_s.identifier)
@legacy_sso.save
Familia.dbclient.hset(@legacy_sso.dbkey, 'enabled', 'true')
Onetime::CustomDomain::SsoConfig.find_by_domain_id(@legacy_dom_s.identifier).enabled?
#=> true

## Legacy on :string model (SsoConfig): quoted '"true"' (correct string
## encoding) loads as the string 'true' and reads enabled
Familia.dbclient.hset(@legacy_sso.dbkey, 'enforce_sso_only', '"true"')
Onetime::CustomDomain::SsoConfig.find_by_domain_id(@legacy_dom_s.identifier).enforce_sso_only?
#=> true

# --- Load-time guard: typo'd spec field fails fast (#3951 AC6) ---

## A typo'd/renamed boolean field in FIELD_SPECS raises
## Familia::Problem at feature-enable time. Without this guard the feature
## would define accessors for the bogus name (satisfying ConfigRegistry's
## method_defined? check) and the failure would surface only as a runtime
## NoMethodError on super.
begin
  Class.new(Familia::Horreum) do
    def self.name = 'BooleanEncodingProbeConfig'
    identifier_field :domain_id
    field :domain_id
    field :enabled
    const_set(
      :FIELD_SPECS,
      {
        'enabled' => { type: :boolean, storage: :string },
        'tpyoed_field' => { type: :boolean, storage: :string },
      }.freeze,
    )
    feature :boolean_encoding
  end
  :no_raise
rescue Familia::Problem => ex
  ex.message.include?("declares boolean field 'tpyoed_field'")
end
#=> true

# --- Cleanup ---

Familia.dbclient.flushdb
OT.info 'Cleaned Redis after config boolean encoding matrix test run'
