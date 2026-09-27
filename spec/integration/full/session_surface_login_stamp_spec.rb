# spec/integration/full/session_surface_login_stamp_spec.rb
#
# frozen_string_literal: true

# Surface-bound sessions (#4409): the marker is stamped by the prepended
# update_session override (apps/web/auth/config/overrides/surface_binding.rb),
# the seam shared by `login` and every Rodauth autologin. This pins, through
# a real HTTP login and the real session codec:
#
#   1. the override is wired ahead of the auth class's own update_session
#      (the active-sessions join-key stamp), so both run;
#   2. the persisted blob carries the string-keyed marker;
#   3. the gate accepts the session on the next request.
#
# LANE: spec:integration:full (lib/tasks/spec.rake). Run it as
#
#   bundle exec rake spec:integration:full

require 'spec_helper'

RSpec.describe 'Session surface stamp at update_session', type: :integration do
  include_context 'auth_rack_test'

  let(:test_password) { 'Test1234!@' }
  let(:test_email) { "surface-stamp-#{SecureRandom.hex(8)}@example.com" }

  def session_blob(sid)
    db    = Familia.dbclient
    dbkey = Onetime::Operations::Sessions::Store.find_key(db, sid)
    codec = Onetime::SessionCodec.from_config
    Onetime::Operations::Sessions::Store.load_data(db, dbkey, codec: codec)
  end

  def login!(email:, password: test_password)
    post_json '/auth/login', { login: email, password: password }
    raise "Login failed for #{email}: #{last_response.status} - #{last_response.body}" unless last_response.status == 200
  end

  it 'prepends the surface stamp ahead of the active-sessions update_session override' do
    ancestors = Auth::Config.ancestors
    stamp     = Auth::Config::Overrides::SurfaceBinding::UpdateSession
    expect(ancestors.index(stamp)).to be < ancestors.index(Auth::Config)
    expect(Auth::Config.instance_method(:update_session).owner).to eq(stamp)
    # The active-sessions `def update_session` is still the class's own
    # definition — reached through `super`, not replaced.
    expect(Auth::Config.instance_method(:update_session).super_method.owner).to eq(Auth::Config)
  end

  it 'persists the string-keyed marker alongside the join key after a real login' do
    account = create_verified_account(db: test_db, email: test_email, password: test_password)
    login!(email: test_email)

    blob = session_blob(rack_mock_session.cookie_jar['onetime.session'])
    expect(blob['account_id']).to eq(account[:id])
    expect(blob['active_session_id_hmac']).to be_a(String)
    expect(blob[Onetime::SessionSurface::KEY]).to eq(Onetime::SessionSurface::CANONICAL)
  end

  it 'is accepted by the surface gate on the following request' do
    create_verified_account(db: test_db, email: test_email, password: test_password)
    login!(email: test_email)

    get_json '/auth/account'
    expect(last_response.status).to eq(200)
  end
end
