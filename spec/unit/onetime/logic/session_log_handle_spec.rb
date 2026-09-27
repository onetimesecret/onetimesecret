# spec/unit/onetime/logic/session_log_handle_spec.rb
#
# frozen_string_literal: true

# #4461: the session id is the bearer credential. Read out of a log it can be
# replayed as the cookie, so no log line carries it. The session store and
# the Web Core controller were switched to the handle first; the logic
# classes and the /auth event logger still logged the id ("Login successful",
# "Login failed", the password-reset lines, [before_logout], [after_logout]
# and the /auth unhandled-exception line) and are pinned here.

require 'spec_helper'
require 'rack/session/abstract/id'

RSpec.describe 'session identifiers in log payloads (#4461)' do
  let(:sid) { 'c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655' }
  let(:session_id) { Rack::Session::SessionId.new(sid) }
  let(:handle) { Onetime::SessionMetadata.handle_for(sid) }

  describe 'Onetime::Logic::Base#session_log_handle' do
    let(:logic_class) do
      Class.new(Onetime::Logic::Base) do
        def initialize(sess) = @sess = sess
        public :session_log_handle, :safe_session_id
      end
    end

    def session_with(id)
      Struct.new(:id).new(id)
    end

    it 'is the keyed handle of the session id, for a Rack SessionId and for a plain String', :aggregate_failures do
      expect(logic_class.new(session_with(session_id)).session_log_handle).to eq(handle)
      expect(logic_class.new(session_with(sid)).session_log_handle).to eq(handle)
      expect(handle).not_to include(sid[0, 16])
    end

    it 'is nil, never an id, when there is no session id (BasicAuth hands the logic a Hash)' do
      expect(logic_class.new({}).session_log_handle).to be_nil
    end

    it 'leaves safe_session_id alone for the callers that need the id itself' do
      expect(logic_class.new(session_with(session_id)).safe_session_id).to eq(session_id)
    end

    it 'is what every logic-class log payload uses: none passes safe_session_id to a logger' do
      offenders = Dir[File.join(Onetime::HOME, '{apps,lib}/**/*.rb')]
        .reject { |path| path.include?('/spec/') }
        .select { |path| File.read(path).match?(/session_id:\s*safe_session_id/) }
        .map { |path| path.delete_prefix("#{Onetime::HOME}/") }

      expect(offenders).to be_empty
    end
  end

  describe 'Auth::Logging' do
    require_relative '../../../../apps/web/auth/lib/logging'

    let(:logger) { instance_double(SemanticLogger::Logger, info: nil, error: nil, debug: nil) }

    before { allow(Onetime).to receive(:get_logger).with('Auth').and_return(logger) }

    {
      log_auth_event: ->(payload) { Auth::Logging.log_auth_event(:before_logout, **payload) },
      log_operation: ->(payload) { Auth::Logging.log_operation(:sync_session, **payload) },
      log_error: ->(payload) { Auth::Logging.log_error(:unhandled_exception, **payload) },
    }.each do |entry_point, emit|
      it "#{entry_point} replaces session_id with session_handle", :aggregate_failures do
        logged = nil
        allow(logger).to receive(:info) { |_message, payload| logged = payload }
        allow(logger).to receive(:error) { |_message, payload| logged = payload }

        emit.call(session_id: session_id, email: 'person@example.com')

        expect(logged).to include(session_handle: handle)
        expect(logged).not_to have_key(:session_id)
        expect(logged.to_s).not_to include(sid)
      end
    end

    it 'accepts the plain String id too' do
      logged = nil
      allow(logger).to receive(:info) { |_message, payload| logged = payload }

      Auth::Logging.log_auth_event(:after_logout, session_id: sid)

      expect(logged).to include(session_handle: handle)
    end

    it 'logs a nil handle, never the value, when the id is blank' do
      logged = nil
      allow(logger).to receive(:info) { |_message, payload| logged = payload }

      Auth::Logging.log_auth_event(:after_logout, session_id: nil)

      expect(logged).to include(session_handle: nil)
      expect(logged).not_to have_key(:session_id)
    end

    it 'adds nothing to a payload that had no session id' do
      logged = nil
      allow(logger).to receive(:info) { |_message, payload| logged = payload }

      Auth::Logging.log_auth_event(:login_success, account_id: 7)

      expect(logged).not_to have_key(:session_handle)
    end
  end
end
