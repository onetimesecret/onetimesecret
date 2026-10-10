# lib/onetime/sso_provider/gitlab.rb
#
# frozen_string_literal: true

# GitLab OAuth2 provider definition (issuerless — platform SSO only; see
# the registry header in lib/onetime/sso_provider/registry.rb).
#
# gitlab.com only: the strategy's site is fixed, with no override for a
# self-managed instance. An issuerless identity is keyed
# (provider, '', uid), and the uid is the GitLab user id, which is unique
# within one GitLab instance only. Moving this route to another instance
# would let that instance's user 42 sign in to the account linked to
# gitlab.com's user 42. Configure a self-managed GitLab as generic OIDC
# instead (OIDC_ISSUER set to the instance URL), which keys identities on
# the instance's issuer.
#
# The strategy is in-repo (gitlab_strategy.rb) rather than the
# omniauth-gitlab gem; that file's header says why.

module Onetime
  module SsoProvider
    module Gitlab
      DEFINITION = {
        key: :gitlab,
        label: 'GitLab',
        strategy: :gitlab,
        gem_require: 'onetime/sso_provider/gitlab_strategy',
        issuer_capable: false,
        required_vars: %w[GITLAB_CLIENT_ID GITLAB_CLIENT_SECRET],
        route_var: 'GITLAB_ROUTE_NAME',
        route_default: 'gitlab',
        display_var: 'GITLAB_DISPLAY_NAME',
        display_default: 'GitLab',
        trust_var: 'GITLAB_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin: 'https://gitlab.com',
        placeholder_options: {
          client_id: 'placeholder',
          client_secret: 'placeholder',
          scope: 'read_user',
        }.freeze,
        strategy_options: -> {
          {
            client_id: ENV.fetch('GITLAB_CLIENT_ID', nil),
            client_secret: ENV.fetch('GITLAB_CLIENT_SECRET', nil),
            scope: 'read_user',
          }
        },
      }.freeze
    end
  end
end
