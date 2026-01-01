# lib/onetime/mail/templates/member_removed.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Notification sent when a member is removed from an organization.
      #
      # Required data:
      #   email_address:     Removed member's email address
      #   organization_name: Organization display name
      #   removed_by:        Email of admin who removed the member
      #
      # Optional data:
      #   removed_at: ISO8601 timestamp of removal
      #   baseuri:    Override site base URI
      #
      class MemberRemoved < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Organization name required' unless data[:organization_name]
          raise ArgumentError, 'Removed by required' unless data[:removed_by]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.member_removed.subject',
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

        def removed_by
          data[:removed_by]
        end

        def removed_at
          @removed_at ||= data[:removed_at] || Time.now.utc.iso8601
        end

        def removed_at_formatted
          time = Time.parse(removed_at.to_s)
          time.utc.strftime('%B %d, %Y at %H:%M UTC')
        rescue ArgumentError
          removed_at.to_s
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
            removed_by: removed_by,
            removed_at: removed_at,
            removed_at_formatted: removed_at_formatted,
            support_path: support_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
