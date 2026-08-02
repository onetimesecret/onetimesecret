# try/integration/api/colonel/config_registry_drift_try.rb
#
# frozen_string_literal: true

# Drift guard for Onetime::CustomDomain::ConfigRegistry and the per-model
# FIELD_SPECS constants it composes (signin/signup/homepage/api/
# incoming own their writable-field specs; sso/mailer contribute none).
#
# Every case WALKS the registry programmatically — no hand-copied field
# lists — so renaming or removing a model field, changing a storage
# encoding, or dropping a serializer key fails HERE even when no endpoint
# test happens to touch that field:
#
# - every spec'd field must have a public reader AND setter on its model
#   (apply_field writes via public_send; the colonel edit form reads back)
# - every spec must be interpretable by coerce_field!/apply_field (type in
#   boolean/enum/string_array, boolean storage native|string), and
#   coerce_field! raises Onetime::Problem on an unknown :type instead of
#   coercing to nil (which apply_field would then write over stored values)
# - boolean specs round-trip: apply true/false -> model predicate
#   true/false -> serializer emits REAL JSON booleans (never 'true'/'false'
#   strings, regardless of the model's storage encoding)
# - enum specs reference frozen, non-empty string-array constants ON the
#   model (object identity, so registry values cannot drift from the
#   model); every declared value round-trips coerce_field! -> apply_field
#   -> serializer; unknown values raise; nullable enums accept nil/'' and
#   serialize nil (clears the override), non-nullable enums reject nil
# - every editable kind's serializer emits every writable field (the edit
#   form must be able to render current values)
# - REDACTION INVARIANT: sso/mailer serializer output never contains
#   client_id/client_secret/api_key values — presence booleans only — and
#   excludes the mailer jsonkey diagnostic blobs
#
# A field added to a model but never spec'd is undetectable intent and is
# deliberately NOT guessed at here.
#
# Run: try --agent try/integration/api/colonel/config_registry_drift_try.rb

require_relative '../../../support/test_helpers'

OT.boot! :test

@registry  = Onetime::CustomDomain::ConfigRegistry
@editable  = @registry.slugs.select { |slug| @registry.editable?(slug) }
@timestamp = Familia.now.to_i

# Walk every editable kind's writable specs: yields [slug, model, field, spec].
def each_writable_spec
  @registry.slugs.select { |slug| @registry.editable?(slug) }.each do |slug|
    model = @registry.model_for(slug)
    @registry.field_specs(slug).each do |field, spec|
      yield(slug, model, field, spec)
    end
  end
end

# A fresh, unsaved config instance for a kind (init defaults applied).
def fresh(slug)
  @registry.model_for(slug).new(domain_id: "drift-#{slug}-#{@timestamp}")
end

# ----------------------------------------------------------------
# Registry shape
# ----------------------------------------------------------------

## The registry catalogs all seven kinds; only sso/mailer are view/delete-only
[@registry.slugs.size, @registry.slugs - @editable]
#=> [7, %w[sso mailer]]

## View-only kinds contribute NO writable field specs
(@registry.slugs - @editable).map { |slug| @registry.field_specs(slug) }
#=> [{}, {}]

## Every editable kind declares at least one writable field
@editable.reject { |slug| @registry.field_specs(slug).any? }
#=> []

## The composed FIELD_SPECS and every per-kind spec hash are frozen
[@registry::FIELD_SPECS.frozen?, @editable.all? { |slug| @registry.field_specs(slug).frozen? }]
#=> [true, true]

# ----------------------------------------------------------------
# Field existence — a stale/renamed spec entry FAILS here
# ----------------------------------------------------------------

## Every writable field has a public reader AND setter on its model
missing = []
each_writable_spec do |slug, model, field, _spec|
  missing << "#{slug}.#{field} (reader)" unless model.method_defined?(field)
  missing << "#{slug}.#{field} (setter)" unless model.method_defined?("#{field}=")
end
missing
#=> []

## Every spec is interpretable by coerce_field!/apply_field (an unknown
## :type raises at request time — the case below guards spec shape too)
bad = []
each_writable_spec do |slug, _model, field, spec|
  case spec[:type]
  when :boolean
    bad << "#{slug}.#{field} storage=#{spec[:storage].inspect}" unless %i[native string].include?(spec[:storage])
  when :enum
    bad << "#{slug}.#{field} missing :values" unless spec.key?(:values)
  when :string_array
    nil # validation delegated to the model setter
  else
    bad << "#{slug}.#{field} type=#{spec[:type].inspect}"
  end
end
bad
#=> []

## coerce_field! RAISES on a spec'd-but-unknown :type instead of silently
## coercing to nil (a misspelled/new type like :integer would otherwise pass
## the load-time setter check AND runtime coercion, then overwrite the
## stored value with nil on every PUT that includes the field). Interpose a
## bogus spec via field_specs — FIELD_SPECS itself is frozen model truth.
@registry.singleton_class.alias_method(:__drift_real_field_specs, :field_specs)
@registry.define_singleton_method(:field_specs) do |_kind|
  { 'drift_field' => { type: :integer } }
end
begin
  begin
    @registry.coerce_field!('signin', 'drift_field', 42)
    'no raise'
  rescue Onetime::Problem => ex
    ex.message
  end
ensure
  @registry.singleton_class.remove_method(:field_specs)
  @registry.singleton_class.alias_method(:field_specs, :__drift_real_field_specs)
  @registry.singleton_class.remove_method(:__drift_real_field_specs)
end
#=> 'drift_field has unknown field spec type :integer (kind=signin)'

## The interposition above was fully restored — the real specs are back
@registry.field_specs('signin').key?('signin_enabled')
#=> true

# ----------------------------------------------------------------
# Boolean specs — apply path and serializer emission
# ----------------------------------------------------------------

## apply_field(true/false) flips the model predicate, whatever the storage encoding
failures = []
each_writable_spec do |slug, _model, field, spec|
  next unless spec[:type] == :boolean

  cfg = fresh(slug)
  @registry.apply_field(cfg, slug, field, true)
  failures << "#{slug}.#{field} apply(true) -> #{cfg.public_send("#{field}?").inspect}" unless cfg.public_send("#{field}?") == true
  @registry.apply_field(cfg, slug, field, false)
  failures << "#{slug}.#{field} apply(false) -> #{cfg.public_send("#{field}?").inspect}" unless cfg.public_send("#{field}?") == false
end
failures
#=> []

## Boolean fields serialize as REAL JSON booleans — never 'true'/'false' strings
failures = []
each_writable_spec do |slug, _model, field, spec|
  next unless spec[:type] == :boolean

  key = field.to_sym
  cfg = fresh(slug)
  @registry.apply_field(cfg, slug, field, true)
  value = @registry.serialize(slug, cfg)[key]
  failures << "#{slug}.#{field} true -> #{value.inspect}" unless value.equal?(true)
  @registry.apply_field(cfg, slug, field, false)
  value = @registry.serialize(slug, cfg)[key]
  failures << "#{slug}.#{field} false -> #{value.inspect}" unless value.equal?(false)
end
failures
#=> []

## No editable-kind serializer value is ever a raw 'true'/'false' storage string
leaks = []
@editable.each do |slug|
  @registry.serialize(slug, fresh(slug)).each do |key, value|
    leaks << "#{slug}.#{key}=#{value.inspect}" if ['true', 'false'].include?(value)
  end
end
leaks
#=> []

# ----------------------------------------------------------------
# Enum specs — constant references and value round-trips
# ----------------------------------------------------------------

## Enum :values are frozen, non-empty string arrays that ARE a constant on
## the model (object identity — inlined literals cannot drift from the model)
bad = []
each_writable_spec do |slug, model, field, spec|
  next unless spec[:type] == :enum

  values = spec[:values]
  bad << "#{slug}.#{field} not-array" unless values.is_a?(Array)
  bad << "#{slug}.#{field} empty" if values.is_a?(Array) && values.empty?
  bad << "#{slug}.#{field} not-frozen" unless values.frozen?
  bad << "#{slug}.#{field} non-strings" unless values.is_a?(Array) && values.all? { |v| v.is_a?(String) }
  referenced = model.constants(false).any? { |name| model.const_get(name).equal?(values) }
  bad << "#{slug}.#{field} values not a #{model} constant" unless referenced
end
bad
#=> []

## Every declared enum value round-trips coerce_field! -> apply_field -> serializer
failures = []
each_writable_spec do |slug, _model, field, spec|
  next unless spec[:type] == :enum

  spec[:values].each do |value|
    coerced = @registry.coerce_field!(slug, field, value)
    failures << "#{slug}.#{field} coerce(#{value}) -> #{coerced.inspect}" unless coerced == value
    cfg = fresh(slug)
    @registry.apply_field(cfg, slug, field, coerced)
    emitted = @registry.serialize(slug, cfg)[field.to_sym]
    failures << "#{slug}.#{field} serialize(#{value}) -> #{emitted.inspect}" unless emitted == value
  end
end
failures
#=> []

## Unknown enum values raise Onetime::Problem for every enum field
accepted = []
each_writable_spec do |slug, _model, field, spec|
  next unless spec[:type] == :enum

  begin
    @registry.coerce_field!(slug, field, 'drift-bogus-value')
    accepted << "#{slug}.#{field}"
  rescue Onetime::Problem
    nil # expected: invalid enum value rejected
  end
end
accepted
#=> []

## Nullable enums accept nil/'' as nil and serialize nil (cleared override);
## non-nullable enums reject nil
failures = []
each_writable_spec do |slug, _model, field, spec|
  next unless spec[:type] == :enum

  if spec[:nullable]
    failures << "#{slug}.#{field} coerce(nil)" unless @registry.coerce_field!(slug, field, nil).nil?
    failures << "#{slug}.#{field} coerce('')" unless @registry.coerce_field!(slug, field, '').nil?
    cfg = fresh(slug)
    @registry.apply_field(cfg, slug, field, nil)
    failures << "#{slug}.#{field} serialize(nil)" unless @registry.serialize(slug, cfg)[field.to_sym].nil?
  else
    begin
      @registry.coerce_field!(slug, field, nil)
      failures << "#{slug}.#{field} accepted nil"
    rescue Onetime::Problem
      nil # expected: non-nullable enum rejects nil
    end
  end
end
failures
#=> []

## string_array specs coerce arrays of strings and reject scalars
failures = []
each_writable_spec do |slug, _model, field, spec|
  next unless spec[:type] == :string_array

  coerced = @registry.coerce_field!(slug, field, ['example.com'])
  failures << "#{slug}.#{field} coerce(array) -> #{coerced.inspect}" unless coerced == ['example.com']
  begin
    @registry.coerce_field!(slug, field, 'example.com')
    failures << "#{slug}.#{field} accepted scalar"
  rescue Onetime::Problem
    nil # expected: non-array rejected
  end
end
failures
#=> []

# ----------------------------------------------------------------
# Serializer coverage — the edit form must be able to render every field
# ----------------------------------------------------------------

## Every editable kind's serializer output includes EVERY writable field
missing = []
@editable.each do |slug|
  data = @registry.serialize(slug, fresh(slug))
  @registry.field_specs(slug).each_key do |field|
    missing << "#{slug}.#{field}" unless data.key?(field.to_sym)
  end
end
missing
#=> []

# ----------------------------------------------------------------
# Redaction invariant — sso/mailer credentials never serialize
# ----------------------------------------------------------------

## sso serializer emits credential PRESENCE booleans only — never the values,
## never client_id/client_secret keys
@sso_domain_id = "drift_sso_#{@timestamp}"
Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @sso_domain_id,
  provider_type: 'oidc',
  client_id: 'drift-client-id-value',
  client_secret: 'drift-client-secret-value',
  issuer: 'https://drift-issuer.example.com',
  enabled: 'true',
)
@sso_data = @registry.serialize('sso', Onetime::CustomDomain::SsoConfig.find_by_domain_id(@sso_domain_id))
@sso_json = JSON.generate(@sso_data)
[@sso_data[:has_client_id].equal?(true), @sso_data[:has_client_secret].equal?(true),
 @sso_data.key?(:client_id), @sso_data.key?(:client_secret),
 @sso_json.include?('drift-client-id-value'), @sso_json.include?('drift-client-secret-value')]
#=> [true, true, false, false, false, false]

## mailer serializer emits api_key presence only; jsonkey diagnostic blobs are
## excluded; the string-boolean verification fields emit REAL booleans
@mailer_domain_id = "drift_mailer_#{@timestamp}"
Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @mailer_domain_id,
  from_address: 'notify@drift.example.com',
  api_key: 'drift-mailer-api-key-value',
)
@mailer_data = @registry.serialize('mailer', Onetime::CustomDomain::MailerConfig.find_by_domain_id(@mailer_domain_id))
@mailer_json = JSON.generate(@mailer_data)
[@mailer_data[:has_api_key].equal?(true),
 @mailer_data.keys & %i[api_key provider_dns_data dns_records dns_check_results],
 @mailer_json.include?('drift-mailer-api-key-value'),
 @mailer_data[:dns_verified].equal?(false), @mailer_data[:provider_verified].equal?(false)]
#=> [true, [], false, true, true]

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
Onetime::CustomDomain::SsoConfig.delete_for_domain!(@sso_domain_id)       rescue nil
Onetime::CustomDomain::MailerConfig.delete_for_domain!(@mailer_domain_id) rescue nil
