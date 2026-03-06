# apps/api/v1/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative 'logic'
require_relative 'controllers'
require_relative 'utils'

module V1
  # V1 API Application
  #
  # Legacy RESTful API for Onetime Secret v1. Maintained for backward
  # compatibility with existing integrations. Serves JSON responses
  # and uses Otto router with controller-based routing.
  #
  # ## Architecture
  #
  # - Router: Otto (configured in `build_router`)
  # - Middleware: Universal (MiddlewareStack) + V1-specific (below)
  # - Otto Hooks: Includes `OttoHooks` for request lifecycle logging
  # - Authentication: HTTP Basic Auth with API token
  #
  # ## V1 Compatibility Policy [#2615]
  #
  # V1 is FROZEN. No new fields or endpoints. New functionality goes to V2/V3.
  # The reconstituted V1 uses receipt/V3 vocabulary internally but MUST emit
  # v0.23.x field names and values in all responses. Governing decisions:
  #
  # 1. FIELD PRESERVATION (additive): V1 responses emit old field names.
  #    Both old and new names MAY coexist but old names MUST be present.
  #    See receipt_hsh in controllers/class_methods.rb for the mapping.
  #    Key renames: metadata_key (not identifier), secret_key (not key),
  #    passphrase_required (not has_passphrase), recipient (not recipients),
  #    metadata_ttl (not receipt_ttl), value (not secret_value).
  #
  # 2. ANONYMOUS ACCESS: preserved. POST /share, /generate, /create, and
  #    POST /secret/:key accept anonymous requests (allow_anonymous=true).
  #
  # 3. AUTH MODES:
  #    - disabled: all V1 endpoints return 404.
  #    - simple: Basic Auth works; session/cookie auth rejected.
  #      Anonymous allowed where allow_anonymous=true.
  #    - full: same as simple for V1. V1 does not require PostgreSQL
  #      or RabbitMQ.
  #
  # 4. STATE VALUES: V1 sends v0.23.x names. previewed -> viewed,
  #    revealed -> received, shared -> new. See V1_STATE_MAP in
  #    controllers/class_methods.rb.
  #
  # 5. CUSTID: V1 emits the customer email address (not the internal
  #    UUID/objid). Controllers pass cust.email to receipt_hsh.
  #
  #
  class Application < Onetime::Application::Base
    include Onetime::Application::OttoHooks

    @uri_prefix = '/api/v1'

    # V1-specific middleware (universal middleware in MiddlewareStack)
    use Rack::JSONBodyParser

    warmup do
    end

    protected

    # Build and configure Otto router instance
    #
    # @return [Otto] Configured router instance
    def build_router
      routes_path = File.join(__dir__, 'routes.txt')
      router      = Otto.new(routes_path)

      # Configure Otto request lifecycle hooks (from OttoHooks module)
      configure_otto_request_hook(router)

      # IP privacy is enabled globally in common middleware stack for public
      # addresses. Must be enabled specifically for private and localhost
      # addresses. See Otto::Middleware::IPPrivacy for details
      router.enable_full_ip_privacy!

      # Default error responses
      headers             = { 'content-type' => 'application/json' }
      router.not_found    = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end
  end
end
