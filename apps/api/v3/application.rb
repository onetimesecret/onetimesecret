# lib/apps/v3/application.rb

require 'roda'

module Onetime
  module API
    module V3
      class Application
        def self.app
          headers = { 'Content-Type' => 'application/json' }
          not_found = [404, headers, [{ message: 'Not Found' }.to_json]]
          server_error = [500, headers, [{ message: 'Internal Server Error' }.to_json]]

          # Create Roda app
          app = Class.new(Roda) do
            plugin :json
            plugin :json_parser
            plugin :all_verbs
            plugin :error_handler

            # Roda routing tree
            route do |r|
              # Routes for v3 API
              r.on "secrets" do
                # GET /secrets
                r.get do
                  { secrets: DB[:secrets].all }
                end

                # POST /secrets
                r.post do
                  id = DB[:secrets].insert(r.params)
                  { id: id }
                end

                # GET /secrets/:id
                r.get Integer do |id|
                  secret = DB[:secrets].where(id: id).first
                  secret || not_found
                end

                # DELETE /secrets/:id
                r.delete Integer do |id|
                  count = DB[:secrets].where(id: id).delete
                  { deleted: count > 0 }
                end
              end

              # Return 404 for unmatched routes
              not_found
            end

            # Error handling
            error do |e|
              OT.ld "[API V3] Error: #{e.message}"
              server_error
            end
          end

          # Build middleware stack around the Roda app
          Rack::Builder.new do
            # Common middleware
            use Rack::Lint
            use Rack::CommonLogger
            use Rack::ContentLength
            use Rack::HandleInvalidUTF8
            use Rack::HandleInvalidPercentEncoding
            use Rack::ClearSessionMessages
            use Rack::DetectHost
            use Onetime::DomainStrategy

            # Add Sentry if available
            if defined?(Sentry::Rack::CaptureExceptions)
              use Sentry::Rack::CaptureExceptions
            end

            # API v3 specific middleware
            # (any v3 specific middleware here)

            # Run the Roda app
            run app.freeze.app
          end
        end
      end
    end
  end
end
