# lib/onetime/operations/email/preview_template.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3. Rendering an email
# template for inspection is site-wide mailer infrastructure with no single
# domain owner. Loaded at the call site (colonel logic + the `bin/ots email
# preview` CLI).
require 'yaml'
require 'onetime/mail'

module Onetime
  module Operations
    module Email
      # Canonical list of previewable / testable templates. SINGLE source of truth
      # shared by the ops, the colonel API, and the CLI (`lib/onetime/cli/email.rb`
      # aliases its `AVAILABLE_TEMPLATES` to this so the value stays byte-identical).
      AVAILABLE_TEMPLATES = [
        :secret_link,
        :welcome,
        :password_request,
        :incoming_secret,
        :feedback_email,
        :secret_revealed,
        :expiration_warning,
        :organization_invitation,
        :email_change_confirmation,
        :email_change_requested,
        :email_changed,
        :new_login_alert,
        :mfa_enabled,
        :mfa_disabled,
        :password_changed,
        :role_changed,
        :member_removed,
        :organization_deleted,
        :trial_expiring,
        :subscription_changed,
      ].freeze

      # Filesystem home of the per-template sample-data YAML fixtures. Same path the
      # CLI used (`lib/onetime/mail/samples`), so preview output is unchanged.
      SAMPLES_PATH = File.expand_path('../../mail/samples', __dir__)

      # Render an email template to text or HTML for visual inspection — the
      # SINGLE implementation of the preview verb (ticket #44). The colonel
      # endpoint (`GET /api/colonel/email/templates/:template/preview`) and the
      # `bin/ots email preview` CLI are thin adapters over it.
      #
      # READ-ONLY: rendering has NO side effects — it never dispatches an email and
      # never touches Redis — so it records NO AdminAuditEvent (CONTRACT 4).
      #
      # ## Behavioural parity
      #
      # Data resolution matches the CLI verbatim: a nil `data` loads the template's
      # sample YAML (injecting the recipient/email_address defaults); a supplied
      # `data` hash is used as-is with the same recipient defaults filled in. The
      # rendered body is exactly what `template.render_text` / `render_html`
      # produced for the CLI.
      class PreviewTemplate
        # Raised when a template has no sample fixture and no data was supplied. The
        # CLI rescues this to print its "No sample data found" hint + exit 1; the
        # colonel logic maps it to a form error. Carries the missing path.
        class MissingSampleError < StandardError
          attr_reader :path

          def initialize(path)
            @path = path
            super("No sample data found: #{path}")
          end
        end

        # @!attribute body [r]
        #   @return [String] the rendered template body (text or HTML).
        Result = Data.define(:template, :locale, :format, :body)

        # @param template [String, Symbol] template name (see {AVAILABLE_TEMPLATES}).
        # @param data [Hash, nil] template variables; nil loads the sample fixture.
        # @param locale [String] locale code for translations.
        # @param format [String] 'html' for the HTML body, anything else for text.
        def initialize(template:, data: nil, locale: 'en', format: 'text')
          @template = template
          @data     = data
          @locale   = locale.to_s.empty? ? 'en' : locale.to_s
          @format   = format.to_s
        end

        # @return [Result]
        # @raise [ArgumentError] when the template name is unknown.
        # @raise [MissingSampleError] when no data + no sample fixture exists.
        def call
          template_data  = resolve_data
          template_class = Onetime::Mail::Mailer.send(:template_class_for, @template.to_sym)
          instance       = template_class.new(template_data, locale: @locale)

          body = if html?
            instance.render_html || '(no HTML template)'
          else
            instance.render_text
          end

          Result.new(template: @template.to_s, locale: @locale, format: html? ? 'html' : 'text', body: body)
        end

        private

        def html?
          @format == 'html'
        end

        # Mirror the CLI's load_data / load_sample_data exactly so preview output is
        # identical whether invoked over HTTP or on a shell.
        def resolve_data
          if @data
            symbolized                   = @data.transform_keys(&:to_sym)
            symbolized[:recipient]     ||= 'preview@example.com'
            symbolized[:email_address] ||= symbolized[:recipient]
            symbolized
          else
            load_sample_data
          end
        end

        def load_sample_data
          sample_file = File.join(SAMPLES_PATH, "#{@template}.yml")
          raise MissingSampleError, sample_file unless File.exist?(sample_file)

          parsed                       = YAML.safe_load_file(sample_file, permitted_classes: [Symbol])
          symbolized                   = parsed.transform_keys(&:to_sym)
          symbolized[:recipient]     ||= symbolized.delete(:email_address) || 'preview@example.com'
          symbolized[:email_address] ||= symbolized[:recipient]
          symbolized
        end
      end
    end
  end
end
