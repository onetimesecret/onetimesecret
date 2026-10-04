# apps/web/auth/spec/support/public_host_rewrite_context.rb
#
# frozen_string_literal: true

# =============================================================================
# SHARED CONTEXT: 'public host rewrite setting'
# =============================================================================
#
# Runs a group with site.network.public_host_rewrite set to the group's
# `rewrite_on` (#4223). The including group defines it, usually once per run:
#
#   [false, true].each do |rewrite|
#     context "with public_host_rewrite #{rewrite ? 'on' : 'off'}" do
#       let(:rewrite_on) { rewrite }
#       include_context 'public host rewrite setting'
#       ...
#
# Onetime::Middleware::PublicHostRewrite reads the setting per request, so
# the mounted stack does not need rebuilding. The setting is put back after
# each example.
#
# Include it ABOVE any `before` that sends requests: hooks run in the order
# they are declared, and a request sent before this one runs is served with
# whatever the setting was.
RSpec.shared_context 'public host rewrite setting' do
  before do
    network                        = (OT.conf['site']['network'] ||= {})
    @public_host_rewrite_had_key   = network.key?('public_host_rewrite')
    @public_host_rewrite_saved     = network['public_host_rewrite']
    network['public_host_rewrite'] = rewrite_on
  end

  after do
    network = (OT.conf['site']['network'] ||= {})
    if @public_host_rewrite_had_key
      network['public_host_rewrite'] = @public_host_rewrite_saved
    else
      network.delete('public_host_rewrite')
    end
  end

  # What the rewrite did to a request: whether it rewrote it, and that the
  # Host as sent is still readable either way.
  def expect_host_rewrite(received_host, rewritten:, env: last_request.env)
    expect(env.key?(Onetime::Middleware::PublicHostRewrite::ORIGINAL_HTTP_HOST)).to eq(rewritten)
    expect(Onetime::Middleware::PublicHostRewrite.original_http_host(env)).to eq(received_host)
  end
end
