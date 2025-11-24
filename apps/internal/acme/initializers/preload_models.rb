# apps/internal/acme/initializers/preload_models.rb
#
# frozen_string_literal: true

# Preload CustomDomain model for ACME validation
#
# Self-registering initializer that ensures the CustomDomain model is
# loaded before ACME endpoints are accessed. This prevents lazy loading
# during Caddy's on-demand TLS requests.
#
# Depends on: :database (models require Redis/Familia connection)
# Provides: :acme_models capability
#
Internal::ACME::Application.initializer(
  :acme_preload_models,
  description: 'Preload CustomDomain model for ACME validation',
  depends_on: [:database],
  provides: [:acme_models]
) do |_ctx|
  require 'onetime/models'
end
