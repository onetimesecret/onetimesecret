# lib/onetime/models/custom_domain/features/safe_dump_fields.rb
#
# frozen_string_literal: true

# Autoloaded extension file for Onetime::CustomDomain SafeDump configuration
# This file is automatically loaded when the SafeDump feature is enabled
module Onetime::CustomDomain::Features
  module SafeDump
    Onetime::CustomDomain.add_feature self, :safe_dump_fields

    # Per-object cached IncomingConfig lookup shared by the incoming_*
    # safe_dump fields below, so dumping all three costs one Redis read
    # (mirrors the @_sso_config_cache / @_mailer_config_cache pattern).
    def self.cached_incoming_config(obj)
      unless obj.instance_variable_defined?(:@_incoming_config_cache)
        obj.instance_variable_set(
          :@_incoming_config_cache,
          Onetime::CustomDomain::IncomingConfig.find_by_domain_id(obj.identifier),
        )
      end
      obj.instance_variable_get(:@_incoming_config_cache)
    end

    def self.included(base)
      base.feature :safe_dump

      base.safe_dump_field :identifier, ->(obj) { obj.identifier }
      base.safe_dump_field :extid
      base.safe_dump_field :domainid
      base.safe_dump_field :display_domain
      base.safe_dump_field :custid
      base.safe_dump_field :base_domain
      base.safe_dump_field :subdomain
      base.safe_dump_field :trd
      base.safe_dump_field :tld
      base.safe_dump_field :sld
      base.safe_dump_field :is_apex, ->(obj) { obj.apex? }
      base.safe_dump_field :txt_validation_host
      base.safe_dump_field :txt_validation_value
      base.safe_dump_field :brand, ->(obj) { obj.brand_settings.to_h } # until we can call obj.brand.to_h
      # NOTE: We don't include brand images here b/c they create huge payloads
      # that we want to avoid unless we are actually going to use it.
      base.safe_dump_field :status
      base.safe_dump_field :vhost, ->(obj) { obj.parse_vhost }
      base.safe_dump_field :vhost_fetch_failed_at, ->(obj) { obj.vhost_fetch_failed_at&.to_i }
      base.safe_dump_field :verified, ->(obj) { obj.verified.to_s == 'true' }
      base.safe_dump_field :created
      base.safe_dump_field :updated

      # SSO status fields - computed from CustomDomain::SsoConfig lookup
      # Single lookup for both fields to avoid N+1 pattern on domain lists.
      # Cache is per-object (cleared on GC when the CustomDomain instance
      # is discarded, typically at end of request).
      base.safe_dump_field :sso_configured,
        ->(obj) {
          config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(obj.identifier)
          obj.instance_variable_set(:@_sso_config_cache, config)
          !config.nil?
        }
      base.safe_dump_field :sso_enabled,
        ->(obj) {
          unless obj.instance_variable_defined?(:@_sso_config_cache)
            obj.instance_variable_set(
              :@_sso_config_cache,
              Onetime::CustomDomain::SsoConfig.find_by_domain_id(obj.identifier),
            )
          end
          obj.instance_variable_get(:@_sso_config_cache)&.enabled? || false
        }
      base.safe_dump_field :sso_enforce_sso_only,
        ->(obj) {
          unless obj.instance_variable_defined?(:@_sso_config_cache)
            obj.instance_variable_set(
              :@_sso_config_cache,
              Onetime::CustomDomain::SsoConfig.find_by_domain_id(obj.identifier),
            )
          end
          obj.instance_variable_get(:@_sso_config_cache)&.enforce_sso_only? || false
        }

      # Homepage config - computed from CustomDomain::HomepageConfig lookup
      # Cache is per-object (cleared on GC when the CustomDomain instance
      # is discarded, typically at end of request) to match the SSO/mailer
      # caching pattern above and avoid a second Redis hit when
      # allow_public_homepage? runs against the same instance.
      #
      # `enabled` here is the STORED flag, deliberately not the effective
      # one: this powers the admin-facing workspace domain list/detail
      # views, which must show the operator's actual selection so editing
      # it (e.g. re-saving 'incoming') never gets short-circuited by a
      # temporary readiness drift. The anonymous-visitor-facing bootstrap
      # payload (DomainSerializer#serialize_homepage_config) uses
      # HomepageConfig#effectively_enabled? instead — the two are
      # intentionally different views of the same record.
      base.safe_dump_field :homepage_config,
        ->(obj) {
          unless obj.instance_variable_defined?(:@_homepage_config_cache)
            obj.instance_variable_set(
              :@_homepage_config_cache,
              Onetime::CustomDomain::HomepageConfig.find_by_domain_id(obj.identifier),
            )
          end
          config = obj.instance_variable_get(:@_homepage_config_cache)
          next nil unless config

          {
            domain_id: config.domain_id,
            enabled: config.enabled?,
            secrets_mode: config.secrets_mode_value,
            signup_enabled: config.signup_enabled?,
            signin_enabled: config.signin_enabled?,
            created_at: config.created&.to_i,
            updated_at: config.updated&.to_i,
          }
        }

      # Incoming config status fields - computed from CustomDomain::IncomingConfig
      # lookup. Single cached lookup for all three fields (same per-object
      # caching pattern as SSO/mailer above, via cached_incoming_config).
      # These let the workspace UI gate the homepage secrets_mode selector on
      # incoming readiness without an extra API round-trip per domain.
      # incoming_ready is server-computed (IncomingConfig#ready?) so the
      # frontend never re-derives — and drifts from — the readiness formula.
      base.safe_dump_field :incoming_configured,
        ->(obj) { !Onetime::CustomDomain::Features::SafeDump.cached_incoming_config(obj).nil? }
      base.safe_dump_field :incoming_enabled,
        ->(obj) { Onetime::CustomDomain::Features::SafeDump.cached_incoming_config(obj)&.enabled? || false }
      base.safe_dump_field :incoming_ready,
        ->(obj) { Onetime::CustomDomain::Features::SafeDump.cached_incoming_config(obj)&.ready? || false }

      # Mail config status fields - computed from CustomDomain::MailerConfig lookup
      # Single lookup for both fields to avoid N+1 pattern on domain lists
      base.safe_dump_field :mail_configured,
        ->(obj) {
          config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(obj.identifier)
          obj.instance_variable_set(:@_mailer_config_cache, config)
          !config.nil?
        }
      base.safe_dump_field :mail_enabled,
        ->(obj) {
          unless obj.instance_variable_defined?(:@_mailer_config_cache)
            obj.instance_variable_set(
              :@_mailer_config_cache,
              Onetime::CustomDomain::MailerConfig.find_by_domain_id(obj.identifier),
            )
          end
          obj.instance_variable_get(:@_mailer_config_cache)&.enabled? || false
        }
    end
  end
end
