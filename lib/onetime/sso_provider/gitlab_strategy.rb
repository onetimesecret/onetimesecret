# lib/onetime/sso_provider/gitlab_strategy.rb
#
# frozen_string_literal: true

# OmniAuth::Strategies::GitLab — the strategy the :gitlab registry definition
# (gitlab.rb) registers. A port of omniauth-gitlab 4.1.0
# (https://github.com/linchus/omniauth-gitlab, lib/omniauth/strategies/gitlab.rb).
#
# WHY NOT THE GEM
#
#   omniauth-gitlab 4.1.0 (2022-09-16, the latest release; master is the
#   same) declares `omniauth-oauth2 ~> 1.8.0`. Bundling it would move the
#   lock from omniauth-oauth2 1.9.0 to 1.8.0 for EVERY OAuth2 provider here
#   (GitHub, Google, Entra ID, Apple). 1.9.0 compares the callback `state`
#   against session['omniauth.state'] in constant time (secure_compare,
#   omniauth/omniauth-oauth2#174; 1.8.0 uses `!=`) and rescues OAuth2
#   timeouts (#169). That state check is the one the OAuth connect-intent
#   binding relies on (AGENTS.md pins omniauth-oauth2 >= 1.9; the Gemfile
#   floors it at ~> 1.9, so the gem no longer resolves at all). The strategy
#   itself is a thin OAuth2 subclass, so it lives here against the locked
#   omniauth-oauth2 instead.
#
#   It is required lazily, like a gem: the definition's gem_require names
#   this file and configure_provider requires it only when the provider
#   registers.
#
# CHANGES FROM UPSTREAM
#
#   - The `redirect_url` option is dropped. Upstream lets it replace
#     callback_url; nothing here sets it, and the callback is always this
#     host's callback path.
#
# Everything else — the gitlab.com site, the api/v4/user lookup, the uid,
# the info/extra shape, the query-less callback_url — is upstream's.
#
# omniauth-gitlab license (MIT), for the ported portions:
#
#   Copyright (c) 2013 ssein
#
#   Permission is hereby granted, free of charge, to any person obtaining
#   a copy of this software and associated documentation files (the
#   "Software"), to deal in the Software without restriction, including
#   without limitation the rights to use, copy, modify, merge, publish,
#   distribute, sublicense, and/or sell copies of the Software, and to
#   permit persons to whom the Software is furnished to do so, subject to
#   the following conditions:
#
#   The above copyright notice and this permission notice shall be
#   included in all copies or substantial portions of the Software.
#
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
#   LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
#   OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
#   WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    class GitLab < OmniAuth::Strategies::OAuth2
      # authorize_url and token_url keep omniauth-oauth2's defaults
      # (/oauth/authorize, /oauth/token), resolved against this site.
      option :client_options, site: 'https://gitlab.com'

      uid { raw_info['id'].to_s }

      info do
        {
          name: raw_info['name'],
          username: raw_info['username'],
          email: raw_info['email'],
          image: raw_info['avatar_url'],
        }
      end

      extra do
        { raw_info: raw_info }
      end

      # GET /api/v4/user — needs the read_user scope.
      def raw_info
        @raw_info ||= access_token.get('api/v4/user').parsed
      end

      # OmniAuth's default appends the request query string. The token
      # exchange sends this value as redirect_uri, and GitLab requires it to
      # match the registered callback URL exactly.
      def callback_url
        full_host + callback_path
      end
    end
  end
end

# So the registry definition can name the strategy by symbol
# (`strategy: :gitlab`); the default camelization would look for `Gitlab`.
OmniAuth.config.add_camelization 'gitlab', 'GitLab'
