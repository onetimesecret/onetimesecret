# lib/onetime/config_generator.rb
#
# frozen_string_literal: true

require 'yaml'
require_relative 'utils/enumerables'

module Onetime
  # Backend for the Configuration Generator JSON API (GET
  # /config-generator/options and /config-generator/render). The interactive
  # UI lives in the docs site, driven by the published config JSON schemas;
  # this module is the machine-facing counterpart (e.g. a future install.sh).
  #
  # NOTE: the docs-site generator carries its own parallel preset manifest
  # (docs repo: src/components/config-generator/presets.ts). Keep the two
  # OPTIONS lists in sync when adding or renaming a preset.
  #
  # Builds small override-file fragments for etc/config.yaml and
  # etc/auth.yaml from a curated set of installer-facing choices. This is
  # deliberately NOT a full re-render of etc/defaults/*.yaml: those files stay
  # the single source of truth, and Onetime::Utils::ConfigResolver deep-merges
  # whatever fragment an operator saves as etc/config.yaml / etc/auth.yaml on
  # top of them at boot. Reusing the real defaults+override merge behavior
  # (rather than reinventing it) means the output here is exactly what an
  # operator would hand-write.
  #
  # OPTIONS is intentionally a small, curated subset of the full config
  # surface (see src/schemas/shapes/config for the exhaustive schema) — just
  # the handful of fork-in-the-road decisions a new self-hoster needs to make
  # (deployment mode, email transport, SSO, custom domains, ...). Keep the
  # TTL choices in lockstep with
  # src/schemas/shapes/config/section/secret_options.ts (ttl_options bounds
  # and default list).
  #
  # Security: never emit a real secret value. Anything secret-bearing
  # (SECRET, database URLs, SMTP/SES/SendGrid/Lettermint credentials) is
  # always rendered as an empty ENV placeholder in env_snippet, never a
  # generated or default value — generator output may end up in a shareable
  # link or a checked-in file.
  module ConfigGenerator
    extend self

    TTL_CHOICES = [
      { value: 300, label: '5 minutes' },
      { value: 1_800, label: '30 minutes' },
      { value: 3_600, label: '1 hour' },
      { value: 14_400, label: '4 hours' },
      { value: 43_200, label: '12 hours' },
      { value: 86_400, label: '1 day' },
      { value: 259_200, label: '3 days' },
      { value: 604_800, label: '7 days' },
      { value: 1_209_600, label: '14 days' },
      { value: 2_592_000, label: '30 days' },
    ].freeze

    OPTIONS = {
      deployment_mode: {
        label: 'Deployment mode',
        description: 'Simple mode uses Redis/Valkey only, no SQL database. ' \
          'Full mode adds PostgreSQL-backed accounts, teams, and SSO.',
        type: 'select',
        default: 'simple',
        choices: [
          { value: 'simple', label: 'Simple — single container, Redis/Valkey only' },
          { value: 'full', label: 'Full — accounts, teams, SSO (adds PostgreSQL)' },
        ],
      },
      email_provider: {
        label: 'Email delivery',
        description: 'How outgoing mail (verification, notifications, password reset) is sent.',
        type: 'select',
        default: 'smtp',
        choices: [
          { value: 'smtp', label: 'Generic SMTP' },
          { value: 'ses', label: 'Amazon SES' },
          { value: 'sendgrid', label: 'SendGrid' },
          { value: 'lettermint', label: 'Lettermint' },
        ],
      },
      sso_enabled: {
        label: 'Single sign-on (SSO)',
        description: 'External identity providers via OmniAuth (OIDC, Entra ID, Google, GitHub). ' \
          'Requires Full deployment mode.',
        type: 'boolean',
        default: false,
        requires: { deployment_mode: 'full' },
      },
      domains_enabled: {
        label: 'Custom domains',
        description: 'Let users share secrets from their own domain instead of the default host.',
        type: 'boolean',
        default: false,
      },
      regions_enabled: {
        label: 'Multi-region / jurisdictions',
        description: 'Advertise multiple regional deployments for data-residency requirements.',
        type: 'boolean',
        default: false,
      },
      diagnostics_enabled: {
        label: 'Error tracking (Sentry)',
        description: 'Report backend, frontend, and worker exceptions to Sentry.',
        type: 'boolean',
        default: false,
      },
      trusted_proxy_enabled: {
        label: 'Behind a reverse proxy / load balancer',
        description: 'Trust X-Forwarded-For from an upstream proxy (nginx, Caddy, ALB, k8s ingress) ' \
          'when resolving client IPs.',
        type: 'boolean',
        default: false,
      },
      passphrase_required: {
        label: 'Require a passphrase on every secret',
        type: 'boolean',
        default: false,
      },
      default_ttl: {
        label: 'Default secret lifetime',
        type: 'select',
        default: 604_800,
        choices: TTL_CHOICES,
      },
    }.freeze

    Result = Struct.new(:config_yaml, :auth_yaml, :env_snippet, :selections, :warnings, keyword_init: true)

    # Selections for the frontend/API: OPTIONS with string keys, ready to
    # serialize as the /config-generator/options JSON response.
    def descriptor
      OPTIONS.transform_keys(&:to_s)
    end

    # @param raw_selections [Hash] string or symbol keys matching OPTIONS;
    #   unknown keys are ignored, missing/invalid values fall back to each
    #   option's default.
    # @return [Result]
    def build(raw_selections = {})
      selections = normalize(raw_selections)
      warnings   = enforce_dependencies(selections)

      Result.new(
        config_yaml: to_yaml_fragment(config_overrides(selections)),
        auth_yaml: to_yaml_fragment(auth_overrides(selections)),
        env_snippet: env_snippet_for(selections),
        selections: selections.transform_keys(&:to_s),
        warnings: warnings,
      )
    end

    private

    def normalize(raw_selections)
      raw_selections = raw_selections || {}

      OPTIONS.each_with_object({}) do |(key, spec), out|
        raw     = raw_selections[key.to_s]
        raw     = raw_selections[key] if raw.nil?
        out[key] = coerce(raw, spec)
      end
    end

    def coerce(raw, spec)
      return spec[:default] if raw.nil?

      case spec[:type]
      when 'boolean'
        raw == true || %w[true 1 yes].include?(raw.to_s.downcase)
      when 'select'
        choice = spec[:choices].find { |c| c[:value].to_s == raw.to_s }
        choice ? choice[:value] : spec[:default]
      else
        raw
      end
    end

    # A selection that requires another selection to hold a specific value
    # (e.g. sso_enabled requires deployment_mode: 'full') is silently reset
    # to its own default when that dependency isn't met, with a warning
    # explaining why — never a hard error, since the API is meant to be
    # forgiving of arbitrary query params.
    def enforce_dependencies(selections)
      warnings = []

      OPTIONS.each do |key, spec|
        requires = spec[:requires]
        next unless requires

        unmet = requires.any? { |dep_key, dep_value| selections[dep_key] != dep_value }
        next unless unmet && selections[key] != spec[:default]

        requirement = requires.map { |k, v| "#{k}: #{v.inspect}" }.join(', ')
        warnings << "#{spec[:label]} requires #{requirement}; ignoring the selected value."
        selections[key] = spec[:default]
      end

      warnings
    end

    def config_overrides(selections)
      {
        'site' => {
          'secret_options' => {
            'default_ttl' => selections[:default_ttl],
            'passphrase' => { 'required' => selections[:passphrase_required] },
          },
          'network' => {
            'trusted_proxy' => { 'enabled' => selections[:trusted_proxy_enabled] },
          },
        },
        'features' => {
          'domains' => { 'enabled' => selections[:domains_enabled] },
          'regions' => { 'enabled' => selections[:regions_enabled] },
        },
        'emailer' => { 'mode' => selections[:email_provider] },
        'diagnostics' => { 'enabled' => selections[:diagnostics_enabled] },
      }
    end

    def auth_overrides(selections)
      overrides = { 'mode' => selections[:deployment_mode] }
      overrides['full'] = { 'features' => { 'sso' => selections[:sso_enabled] } } if selections[:deployment_mode] == 'full'
      overrides
    end

    def to_yaml_fragment(hash)
      normalized = Onetime::Utils::Enumerables.normalize_keys(hash)
      YAML.dump(normalized).sub(/\A---\n/, '')
    end

    def env_snippet_for(selections)
      lines = [
        '# Secrets — generate and store these yourself; never commit them',
        '# or paste them into a shared link.',
        'SECRET=',
      ]

      if selections[:deployment_mode] == 'full'
        lines << 'AUTH_DATABASE_URL='
        lines << 'ARGON2_SECRET='
      end

      case selections[:email_provider]
      when 'smtp'
        lines.concat(%w[SMTP_HOST= SMTP_USERNAME= SMTP_PASSWORD=])
      when 'ses'
        lines.concat(%w[AWS_ACCESS_KEY_ID= AWS_SECRET_ACCESS_KEY=])
      when 'sendgrid'
        lines << 'SENDGRID_API_KEY='
      when 'lettermint'
        lines.concat(%w[LETTERMINT_API_TOKEN= LETTERMINT_TEAM_TOKEN=])
      end

      lines << 'SENTRY_DSN_BACKEND=' if selections[:diagnostics_enabled]

      "#{lines.join("\n")}\n"
    end
  end
end
