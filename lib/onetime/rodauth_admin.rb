# lib/onetime/rodauth_admin.rb
#
# frozen_string_literal: true

require 'erb'

module Onetime
  # Outbound links to the standalone Rodauth Admin instance
  # (onetimesecret/rodauth-admin), the tool that administers the SQL-backed
  # accounts behind full auth mode.
  #
  # This is the whole of the main repo's side of that integration: a base URL
  # from config (`site.admin.rodauth_admin_url`, env RODAUTH_ADMIN_URL) and
  # two link builders. Nothing is ever requested from the admin — no
  # credential, no shared session, no cross-service call — so the URL is
  # optional everywhere, including production. Unset means every caller
  # renders plain text instead of a link.
  #
  # Both links are gated on full auth mode. In simple mode there is no accounts
  # table, so there is nothing on the far side to link to; a configured URL is
  # simply ignored rather than producing a link to a page that cannot resolve.
  module RodauthAdmin
    extend self

    # Configured base URL with any trailing slash removed, or nil when unset or
    # blank. Mode-agnostic: this is the raw setting.
    #
    # @return [String, nil]
    def base_url
      raw = OT.conf&.dig('site', 'admin', 'rodauth_admin_url').to_s.strip
      return nil if raw.empty?

      raw.sub(%r{/+\z}, '')
    end

    # True when a link can be rendered: full auth mode AND a configured URL.
    def linkable?
      Onetime.auth_config.full_enabled? && !base_url.nil?
    end

    # Landing page of the admin, for surfaces that hand the operator over
    # without a specific account in mind (the sessions console banner).
    #
    # @return [String, nil]
    def console_url
      base_url if linkable?
    end

    # Deep link to the Rodauth account joined to a customer by
    # `accounts.external_id == Customer.extid`. Targets the admin's lookup
    # route (`/account?q=<external_id>`), which is its documented inbound link
    # from the colonel console: a single hit redirects to the canonical
    # /accounts/<id> page, and an orphaned or unknown extid lands on a proper
    # miss page rather than a 404.
    #
    # @param extid [String, nil] the customer's public id
    # @return [String, nil] nil when unset, not in full mode, or no extid
    def account_url(extid)
      base  = console_url
      value = extid.to_s.strip
      return nil if base.nil? || value.empty?

      "#{base}/account?q=#{ERB::Util.url_encode(value)}"
    end
  end
end
