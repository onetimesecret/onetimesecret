# PoC 04 — Verification that Onetime::Session inherits Rack's DEFAULT_OPTIONS.
#
# REFUTES the source-only reading that the subclass shadows Rack's defaults and
# therefore loses HttpOnly / Path / cookie_only / the CSPRNG. The guard in
# lib/onetime/session.rb:63 is `unless defined?(DEFAULT_OPTIONS)`, and Ruby's
# constant lookup finds the INHERITED constant through the ancestor chain — so
# the constant is never defined on the subclass at all.
#
# Run (from the repo root, with the env from tooling.md sourced):
#   bundle exec ruby -Ilib docs/security/2026-08-14-appsec-review/poc/04-session-options-verification.rb
require 'onetime'
OT.execution_mode = :backend
Onetime.boot! :app

sess = Onetime::Session.new(->(_env) { [200, {}, []] }, {
  secret: OT.conf.dig('site', 'secret'),
  expire_after: 86_400, key: 'onetime.session', secure: true, same_site: :lax
})

opts = sess.instance_variable_get(:@default_options)
puts "default_options keys: #{opts.keys.sort.inspect}"
puts "  httponly                   = #{opts[:httponly].inspect}"
puts "  path                       = #{opts[:path].inspect}"
puts "  secure_random(@sid_secure) = #{sess.instance_variable_get(:@sid_secure).inspect}"
puts "  @cookie_only               = #{sess.instance_variable_get(:@cookie_only).inspect}"
puts

# If generate_sid used Kernel.rand, reseeding would replay the same ids.
srand(12_345); a = 3.times.map { sess.send(:generate_sid) }
srand(12_345); b = 3.times.map { sess.send(:generate_sid) }
puts "sid sample: #{a.first}"
puts "REPRODUCIBLE AFTER srand()? #{a == b}   (true would mean Kernel.rand, NOT a CSPRNG)"
