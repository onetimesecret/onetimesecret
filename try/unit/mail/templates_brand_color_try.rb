# try/unit/mail/templates_brand_color_try.rb
#
# frozen_string_literal: true

#
# TemplateContext brand-aware helpers (issue #3048 / #3049)
#
# Covers Task 4 (TemplateContext helpers in lib/onetime/mail/views/base.rb)
# and Task 8 (12 email templates) of the branding port.
#
# Critical assertions:
#   - brand_color resolves data -> brand conf -> neutral blue (#3B82F6)
#   - logo_url resolves brand conf -> nil (NOT the OTS logo path)
#   - support_email resolves brand conf -> GLOBAL_DEFAULTS (NOT the OTS address)
#   - logo_alt delegates to product_name
#   - site_product_name resolves brand -> site_name -> 'OTS'
#   - The 12 shipped HTML templates contain no #dc4a22 or onetime-logo-v3-xl.svg
#     (regression guard against re-introduction).
#
# Most tests are FORWARD-LOOKING — they will fail until the email-template
# purge in Task 8 lands. The TemplateContext helpers themselves are already
# in place per Wave 1 commit b98ef1768.
#

require_relative '../../support/test_helpers'

# Boot to populate OT.conf for fallback chain tests.
OT.boot! :test, false

# Load the mail module so Onetime::Mail::Templates::Base::TemplateContext is
# available.
require 'onetime/mail'

@ctx_class = Onetime::Mail::Templates::Base::TemplateContext
@constants = Onetime::CustomDomain::BrandSettingsConstants

# Snapshot the original config once so each test that mutates OT.conf can
# restore it in an ensure block. Using YAML round-trip for a deep clone.
@_saved_conf = YAML.load(YAML.dump(OT.conf))

# Helper that runs a block with OT.conf['brand'] set to brand_hash, then
# restores the original config. Returns the block's value.
def with_brand_conf(brand_hash)
  saved = YAML.load(YAML.dump(OT.conf))
  conf_copy = YAML.load(YAML.dump(saved))
  conf_copy['brand'] = brand_hash
  OT.send(:conf=, conf_copy)
  yield
ensure
  OT.send(:conf=, saved) rescue nil
end

# Helper that runs a block with OT.conf['brand'] removed entirely, then
# restores the original config. Returns the block's value.
def without_brand_conf
  saved = YAML.load(YAML.dump(OT.conf))
  conf_copy = YAML.load(YAML.dump(saved))
  conf_copy.delete('brand')
  OT.send(:conf=, conf_copy)
  yield
ensure
  OT.send(:conf=, saved) rescue nil
end

# TRYOUTS

# ============================================================================
# brand_color fallback chain
# ============================================================================

## brand_color returns @data[:brand_color] when set (highest precedence)
ctx = @ctx_class.new({ brand_color: '#abcdef' }, 'en')
ctx.brand_color
#=> '#abcdef'

## brand_color falls through to OT.conf['brand']['primary_color'] when @data unset
with_brand_conf({ 'primary_color' => '#112233' }) do
  ctx = @ctx_class.new({}, 'en')
  ctx.brand_color
end
#=> '#112233'

## brand_color falls through to BrandSettingsConstants::DEFAULTS when neither set
without_brand_conf do
  ctx = @ctx_class.new({}, 'en')
  ctx.brand_color
end
#=> '#3B82F6'

## [regression guard] BrandSettingsConstants::DEFAULTS[:primary_color] is neutral blue
@constants::DEFAULTS[:primary_color]
#=> '#3B82F6'

## [regression guard] BrandSettingsConstants::DEFAULTS[:primary_color] is NOT OTS-orange
@constants::DEFAULTS[:primary_color] != '#dc4a22'
#=> true

## brand_color is memoized — calling twice returns the same value
without_brand_conf do
  ctx = @ctx_class.new({ brand_color: '#deadbe' }, 'en')
  first  = ctx.brand_color
  second = ctx.brand_color
  first == second && first == '#deadbe'
end
#=> true

# ============================================================================
# logo_url fallback chain
# ============================================================================

## logo_url returns OT.conf['brand']['logo_url'] when set
with_brand_conf({ 'logo_url' => 'https://example.test/logo.svg' }) do
  ctx = @ctx_class.new({}, 'en')
  ctx.logo_url
end
#=> 'https://example.test/logo.svg'

## logo_url returns nil when no brand config (neutralized fallback per #3049)
without_brand_conf do
  ctx = @ctx_class.new({}, 'en')
  ctx.logo_url
end
#=> nil

## [regression guard] logo_url NEVER returns OTS-branded asset path
without_brand_conf do
  ctx = @ctx_class.new({}, 'en')
  result = ctx.logo_url
  result.nil? || !result.include?('onetime-logo-v3-xl.svg')
end
#=> true

## logo_url is memoized — even when value is nil, conf is not re-resolved
without_brand_conf do
  ctx = @ctx_class.new({}, 'en')
  ctx.logo_url
  # After first call, mutate conf — memoized value should not change
  conf_copy = YAML.load(YAML.dump(OT.conf))
  conf_copy['brand'] = { 'logo_url' => 'https://later.test/logo.svg' }
  OT.send(:conf=, conf_copy)
  ctx.logo_url
end
#=> nil

## [regression guard] BrandSettingsConstants::GLOBAL_DEFAULTS[:logo_url] is nil
@constants::GLOBAL_DEFAULTS[:logo_url]
#=> nil

# ============================================================================
# support_email fallback chain
# ============================================================================

## support_email returns OT.conf['brand']['support_email'] when set
with_brand_conf({ 'support_email' => 'help@acme.test' }) do
  ctx = @ctx_class.new({}, 'en')
  ctx.support_email
end
#=> 'help@acme.test'

## support_email falls back to GLOBAL_DEFAULTS[:support_email] (nil) when unset
without_brand_conf do
  ctx = @ctx_class.new({}, 'en')
  ctx.support_email
end
#=> nil

## [regression guard] support_email NEVER returns 'support@onetimesecret.com'
without_brand_conf do
  ctx = @ctx_class.new({}, 'en')
  result = ctx.support_email
  result.nil? || result != 'support@onetimesecret.com'
end
#=> true

## [regression guard] BrandSettingsConstants::GLOBAL_DEFAULTS[:support_email] is neutralized
@constants::GLOBAL_DEFAULTS[:support_email] != 'support@onetimesecret.com'
#=> true

# ============================================================================
# signature_name fallback chain (email sign-off — no longer "Delano")
# ============================================================================

## signature_name returns @data[:signature_name] when set (domain-level override wins)
ctx = @ctx_class.new({ signature_name: 'DomainTeam' }, 'en')
ctx.signature_name
#=> 'DomainTeam'

## signature_name falls through to OT.conf['brand']['signature_name'] when @data unset
with_brand_conf({ 'signature_name' => 'Jane from Acme' }) do
  ctx = @ctx_class.new({}, 'en')
  ctx.signature_name
end
#=> 'Jane from Acme'

## @data[:signature_name] supersedes the install-level brand config
with_brand_conf({ 'signature_name' => 'Install Co' }) do
  ctx = @ctx_class.new({ signature_name: 'DomainTeam' }, 'en')
  ctx.signature_name
end
#=> 'DomainTeam'

## signature_name returns nil when unset, so templates fall back to the i18n default
without_brand_conf do
  ctx = @ctx_class.new({}, 'en')
  ctx.signature_name
end
#=> nil

## signature_name is decoupled from product_name (setting product_name does not leak in)
with_brand_conf({ 'product_name' => 'Acme Secrets' }) do
  ctx = @ctx_class.new({}, 'en')
  ctx.signature_name
end
#=> nil

## signature_name memoizes nil — mutating conf after first call does not change result
without_brand_conf do
  ctx = @ctx_class.new({}, 'en')
  ctx.signature_name
  conf_copy = YAML.load(YAML.dump(OT.conf))
  conf_copy['brand'] = { 'signature_name' => 'LaterName' }
  OT.send(:conf=, conf_copy)
  ctx.signature_name
end
#=> nil

## [regression guard] BrandSettingsConstants::GLOBAL_DEFAULTS[:signature_name] is nil
@constants::GLOBAL_DEFAULTS[:signature_name]
#=> nil

# ============================================================================
# logo_alt delegates to product_name
# ============================================================================

## logo_alt returns the same value as product_name when product_name is from data
ctx = @ctx_class.new({ product_name: 'Acme Secrets' }, 'en')
[ctx.logo_alt, ctx.product_name]
#=> ['Acme Secrets', 'Acme Secrets']

## logo_alt delegates to product_name when falling through to site_product_name
without_brand_conf do
  ctx = @ctx_class.new({}, 'en')
  ctx.logo_alt == ctx.product_name
end
#=> true

# ============================================================================
# site_product_name fallback chain
# ============================================================================

## site_product_name returns OT.conf['brand']['product_name'] when set
with_brand_conf({ 'product_name' => 'Acme' }) do
  ctx = @ctx_class.new({}, 'en')
  ctx.site_product_name
end
#=> 'Acme'

## site_product_name falls through to site.interface.ui.header.site_name when brand absent
saved = YAML.load(YAML.dump(OT.conf))
begin
  conf_copy = YAML.load(YAML.dump(saved))
  conf_copy.delete('brand')
  conf_copy['site'] ||= {}
  conf_copy['site']['interface'] ||= {}
  conf_copy['site']['interface']['ui'] ||= {}
  conf_copy['site']['interface']['ui']['header'] ||= {}
  conf_copy['site']['interface']['ui']['header']['branding'] ||= {}
  conf_copy['site']['interface']['ui']['header']['branding']['site_name'] = 'LegacySiteName'
  OT.send(:conf=, conf_copy)
  ctx = @ctx_class.new({}, 'en')
  ctx.site_product_name
ensure
  OT.send(:conf=, saved) rescue nil
end
#=> 'LegacySiteName'

## site_product_name falls through to GLOBAL_DEFAULTS[:product_name] (= 'OTS')
saved = YAML.load(YAML.dump(OT.conf))
begin
  conf_copy = YAML.load(YAML.dump(saved))
  conf_copy.delete('brand')
  # Make sure no site_name is present so the third tier is exercised.
  if conf_copy.dig('site', 'interface', 'ui', 'header', 'branding')
    conf_copy['site']['interface']['ui']['header']['branding'].delete('site_name')
  end
  OT.send(:conf=, conf_copy)
  ctx = @ctx_class.new({}, 'en')
  ctx.site_product_name
ensure
  OT.send(:conf=, saved) rescue nil
end
#=> 'OTS'

## [regression guard] GLOBAL_DEFAULTS[:product_name] is 'OTS', not 'Onetime Secret'
@constants::GLOBAL_DEFAULTS[:product_name]
#=> 'OTS'

# ============================================================================
# Carried-forward helpers — verify they still work post-port
# ============================================================================

## h helper escapes HTML
ctx = @ctx_class.new({}, 'en')
ctx.h('<x>')
#=> '&lt;x&gt;'

## u helper URL-encodes
ctx = @ctx_class.new({}, 'en')
ctx.u('hello world')
#=> 'hello%20world'

## t helper returns a String
ctx = @ctx_class.new({}, 'en')
ctx.t('email.common.greeting').is_a?(String)
#=> true

## baseuri uses data[:baseuri] when provided
ctx = @ctx_class.new({ baseuri: 'https://custom.test' }, 'en')
ctx.baseuri
#=> 'https://custom.test'

## baseuri falls back to site_baseuri when data[:baseuri] absent
ctx = @ctx_class.new({}, 'en')
ctx.baseuri.is_a?(String) && !ctx.baseuri.empty?
#=> true

## product_name uses data override
ctx = @ctx_class.new({ product_name: 'Override' }, 'en')
ctx.product_name
#=> 'Override'

## display_domain prefers data[:display_domain]
ctx = @ctx_class.new({ display_domain: 'custom.test', share_domain: 'share.test' }, 'en')
ctx.display_domain
#=> 'custom.test'

## display_domain uses share_domain as next fallback
ctx = @ctx_class.new({ share_domain: 'share.test' }, 'en')
ctx.display_domain
#=> 'share.test'

## site_host returns a non-empty String
ctx = @ctx_class.new({}, 'en')
ctx.site_host.is_a?(String) && !ctx.site_host.empty?
#=> true

## site_baseuri returns a String starting with http(s)://
ctx = @ctx_class.new({}, 'en')
uri = ctx.site_baseuri
uri.is_a?(String) && uri.start_with?('http')
#=> true

## conf_dig (via send, since it's private) returns OT.conf values
ctx = @ctx_class.new({}, 'en')
ctx.send(:conf_dig, 'site').is_a?(Hash)
#=> true

# ============================================================================
# Email-template purge regression guard
# ============================================================================
#
# These tests are FORWARD-LOOKING — they will fail until Task 8 (12-template
# purge) lands. The guard ensures #dc4a22 and onetime-logo-v3-xl.svg never
# slip back into shipped HTML email templates.
#
# Glob is inlined per-test because tryouts evaluates each test case in an
# evaluator that doesn't see methods defined after `# TRYOUTS`.

## [forward / regression guard] no shipped HTML email template contains '#dc4a22'
files = Dir.glob(File.join(ENV.fetch('ONETIME_HOME'), 'lib/onetime/mail/templates/*.html.erb'))
offenders = files.select { |path| File.read(path).include?('#dc4a22') }
offenders.map { |p| File.basename(p) }.sort
#=> []

## [forward / regression guard] no shipped HTML email template contains 'onetime-logo-v3-xl.svg'
files = Dir.glob(File.join(ENV.fetch('ONETIME_HOME'), 'lib/onetime/mail/templates/*.html.erb'))
offenders = files.select { |path| File.read(path).include?('onetime-logo-v3-xl.svg') }
offenders.map { |p| File.basename(p) }.sort
#=> []

## All 13 expected HTML templates are present (purge audit baseline)
Dir.glob(File.join(ENV.fetch('ONETIME_HOME'), 'lib/onetime/mail/templates/*.html.erb')).size
#=> 13

## [regression guard] no shipped email template hardcodes the 'Delano' sign-off
files = Dir.glob(File.join(ENV.fetch('ONETIME_HOME'), 'lib/onetime/mail/templates/*.erb'))
offenders = files.select { |path| File.read(path).include?('Delano') }
offenders.map { |p| File.basename(p) }.sort
#=> []

# ============================================================================
# Memoization across config mutation (gap 5 — issue #3048)
# ============================================================================
#
# brand_color, support_email, site_product_name MUST be memoized per-instance.
# Mutating OT.conf['brand'] after the first call must NOT change the cached
# return value. logo_url is already covered above (lines 134-143). These
# guard against re-resolution that would let a stale TemplateContext drift
# mid-render if config flips during background reload.

## brand_color memoizes — mutating OT.conf after first call does not change result
@_initial_conf = YAML.load(YAML.dump(OT.conf))
begin
  conf_copy = YAML.load(YAML.dump(@_initial_conf))
  conf_copy['brand'] = { 'primary_color' => '#111111' }
  OT.send(:conf=, conf_copy)
  ctx = @ctx_class.new({}, 'en')
  first = ctx.brand_color
  # Mutate brand conf to a new color
  next_conf = YAML.load(YAML.dump(conf_copy))
  next_conf['brand'] = { 'primary_color' => '#222222' }
  OT.send(:conf=, next_conf)
  second = ctx.brand_color
  [first, second]
ensure
  OT.send(:conf=, @_initial_conf) rescue nil
end
#=> ['#111111', '#111111']

## support_email memoizes — mutating OT.conf after first call does not change result
@_initial_conf2 = YAML.load(YAML.dump(OT.conf))
begin
  conf_copy = YAML.load(YAML.dump(@_initial_conf2))
  conf_copy['brand'] = { 'support_email' => 'first@acme.test' }
  OT.send(:conf=, conf_copy)
  ctx = @ctx_class.new({}, 'en')
  first = ctx.support_email
  next_conf = YAML.load(YAML.dump(conf_copy))
  next_conf['brand'] = { 'support_email' => 'second@acme.test' }
  OT.send(:conf=, next_conf)
  second = ctx.support_email
  [first, second]
ensure
  OT.send(:conf=, @_initial_conf2) rescue nil
end
#=> ['first@acme.test', 'first@acme.test']

## site_product_name memoizes — mutating OT.conf after first call does not change result
@_initial_conf3 = YAML.load(YAML.dump(OT.conf))
begin
  conf_copy = YAML.load(YAML.dump(@_initial_conf3))
  conf_copy['brand'] = { 'product_name' => 'FirstName' }
  OT.send(:conf=, conf_copy)
  ctx = @ctx_class.new({}, 'en')
  first = ctx.site_product_name
  next_conf = YAML.load(YAML.dump(conf_copy))
  next_conf['brand'] = { 'product_name' => 'SecondName' }
  OT.send(:conf=, next_conf)
  second = ctx.site_product_name
  [first, second]
ensure
  OT.send(:conf=, @_initial_conf3) rescue nil
end
#=> ['FirstName', 'FirstName']

# ============================================================================
# TemplateContext fallback when OT.conf is nil (gap 7 — issue #3048)
# ============================================================================
#
# conf_dig must guard against OT.conf being nil so that helpers degrade
# to GLOBAL_DEFAULTS-level fallbacks instead of raising. Setting @conf
# directly (rather than via the setter) bypasses any wrapping behavior.

## OT.conf=nil — brand_color falls through to DEFAULTS without raising
@_saved_for_nil = OT.instance_variable_get(:@conf)
begin
  OT.instance_variable_set(:@conf, nil)
  ctx = @ctx_class.new({}, 'en')
  ctx.brand_color
ensure
  OT.instance_variable_set(:@conf, @_saved_for_nil)
end
#=> '#3B82F6'

## OT.conf=nil — support_email falls through to GLOBAL_DEFAULTS (nil)
@_saved_for_nil2 = OT.instance_variable_get(:@conf)
begin
  OT.instance_variable_set(:@conf, nil)
  ctx = @ctx_class.new({}, 'en')
  ctx.support_email
ensure
  OT.instance_variable_set(:@conf, @_saved_for_nil2)
end
#=> nil

## OT.conf=nil — logo_url falls through to GLOBAL_DEFAULTS (nil)
@_saved_for_nil3 = OT.instance_variable_get(:@conf)
begin
  OT.instance_variable_set(:@conf, nil)
  ctx = @ctx_class.new({}, 'en')
  ctx.logo_url
ensure
  OT.instance_variable_set(:@conf, @_saved_for_nil3)
end
#=> nil

## OT.conf=nil — site_product_name falls through to GLOBAL_DEFAULTS ('OTS')
@_saved_for_nil4 = OT.instance_variable_get(:@conf)
begin
  OT.instance_variable_set(:@conf, nil)
  ctx = @ctx_class.new({}, 'en')
  ctx.site_product_name
ensure
  OT.instance_variable_set(:@conf, @_saved_for_nil4)
end
#=> 'OTS'

## OT.conf=nil — signature_name degrades to nil without raising
@_saved_for_nil_sig = OT.instance_variable_get(:@conf)
begin
  OT.instance_variable_set(:@conf, nil)
  ctx = @ctx_class.new({}, 'en')
  ctx.signature_name
ensure
  OT.instance_variable_set(:@conf, @_saved_for_nil_sig)
end
#=> nil

## OT.conf=nil — site_host degrades to 'localhost'
@_saved_for_nil5 = OT.instance_variable_get(:@conf)
begin
  OT.instance_variable_set(:@conf, nil)
  ctx = @ctx_class.new({}, 'en')
  ctx.site_host
ensure
  OT.instance_variable_set(:@conf, @_saved_for_nil5)
end
#=> 'localhost'
