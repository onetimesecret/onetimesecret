# spec/support/helpers/entitlement_preview_helpers.rb
#
# frozen_string_literal: true

# Helpers for exercising the request-scoped entitlement preview context
# (ADR-020). In production the Fiber-local is populated by
# Onetime::Middleware::EntitlementPreviewContext and cleared in its ensure
# block; specs that invoke models or logic directly bypass the middleware,
# so they need the same set/ensure-clear discipline around a block.
module EntitlementPreviewHelpers
  # Run a block with an active entitlement preview context. Always clears
  # the Fiber-local afterwards so preview state cannot leak into other
  # examples on the same thread.
  #
  # @param planid [String, nil] Preview plan id (drives limit_for)
  # @param grants_key [String, nil] Redis key of the session grants set
  # @param revokes_key [String, nil] Redis key of the session revokes set
  # @return [Object] The block's return value
  def with_entitlement_preview(planid: nil, grants_key: nil, revokes_key: nil)
    Onetime::EntitlementPreview.set(
      planid: planid,
      grants_key: grants_key,
      revokes_key: revokes_key,
    )
    yield
  ensure
    Onetime::EntitlementPreview.clear
  end
end

RSpec.configure do |config|
  config.include EntitlementPreviewHelpers
end
