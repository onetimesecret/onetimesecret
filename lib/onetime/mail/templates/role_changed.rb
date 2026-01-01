# lib/onetime/mail/templates/role_changed.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Notification sent when a member's role is changed in an organization.
      #
      # Required data:
      #   email_address:     Member's email address
      #   organization_name: Organization display name
      #   old_role:          Previous role (e.g., 'member', 'admin')
      #   new_role:          New role (e.g., 'member', 'admin')
      #
      # Optional data:
      #   changed_by: Email of admin who changed the role
      #   changed_at: ISO8601 timestamp of change
      #   baseuri:    Override site base URI
      #
      class RoleChanged < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Organization name required' unless data[:organization_name]
          raise ArgumentError, 'Old role required' unless data[:old_role]
          raise ArgumentError, 'New role required' unless data[:new_role]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.role_changed.subject',
            locale: locale,
            organization_name: organization_name,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def organization_name
          data[:organization_name]
        end

        def old_role
          data[:old_role]
        end

        def new_role
          data[:new_role]
        end

        def old_role_display
          translate_role(old_role)
        end

        def new_role_display
          translate_role(new_role)
        end

        def changed_by
          data[:changed_by]
        end

        def changed_at
          data[:changed_at] || Time.now.utc.iso8601
        end

        def changed_at_formatted
          time = Time.parse(changed_at.to_s)
          time.strftime('%B %d, %Y at %H:%M UTC')
        rescue ArgumentError
          changed_at.to_s
        end

        def organization_settings_path
          '/account/organizations'
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def translate_role(role)
          role_key = %w[admin owner member].include?(role) ? role : 'member'
          EmailTranslations.translate(
            "email.role_changed.roles.#{role_key}",
            locale: locale,
          )
        end

        def site_ssl?
          return true unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'ssl') != false
        end

        def site_host
          return 'onetimesecret.com' unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'host') || 'onetimesecret.com'
        end

        def site_baseuri
          scheme = site_ssl? ? 'https://' : 'http://'
          "#{scheme}#{site_host}"
        end

        def template_binding
          computed_data = data.merge(
            organization_name: organization_name,
            old_role: old_role,
            new_role: new_role,
            old_role_display: old_role_display,
            new_role_display: new_role_display,
            changed_by: changed_by,
            changed_at: changed_at,
            changed_at_formatted: changed_at_formatted,
            organization_settings_path: organization_settings_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
