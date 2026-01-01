# lib/onetime/mail/templates/organization_deleted.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Notification sent to all members when an organization is deleted.
      #
      # Required data:
      #   email_address:     Member's email address
      #   organization_name: Organization display name
      #   deleted_by:        Email of admin who deleted the organization
      #
      # Optional data:
      #   deleted_at: ISO8601 timestamp of deletion
      #   baseuri:    Override site base URI
      #
      class OrganizationDeleted < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Organization name required' unless data[:organization_name]
          raise ArgumentError, 'Deleted by required' unless data[:deleted_by]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.organization_deleted.subject',
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

        def deleted_by
          data[:deleted_by]
        end

        def deleted_at
          data[:deleted_at] || Time.now.utc.iso8601
        end

        def deleted_at_formatted
          time = Time.parse(deleted_at.to_s)
          time.strftime('%B %d, %Y at %H:%M UTC')
        rescue ArgumentError
          deleted_at.to_s
        end

        def support_path
          '/support'
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def template_binding
          computed_data = data.merge(
            organization_name: organization_name,
            deleted_by: deleted_by,
            deleted_at: deleted_at,
            deleted_at_formatted: deleted_at_formatted,
            support_path: support_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
