# lib/onetime/mail/templates/organization_invitation.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Organization invitation email template.
      #
      # Sent when an organization owner/admin invites someone to join.
      #
      # Required data:
      #   invited_email:       Recipient email address
      #   organization_name:   Organization display name
      #   inviter_email:       Email of the person who sent the invite
      #   role:                Role being offered (member, admin)
      #   invite_token:        Secure invitation token
      #
      # Optional data:
      #   expires_in_days:     Days until invitation expires (default: 7)
      #   baseuri:             Override site base URI
      #
      class OrganizationInvitation < Base
        DEFAULT_EXPIRY_DAYS = 7

        protected

        def validate_data!
          raise ArgumentError, 'Invited email required' unless data[:invited_email]
          raise ArgumentError, 'Organization name required' unless data[:organization_name]
          raise ArgumentError, 'Inviter email required' unless data[:inviter_email]
          raise ArgumentError, 'Invite token required' unless data[:invite_token]
        end

        public

        def subject
          # TODO: I18n.t('email.organization_invitation.subject', org: organization_name)
          "You've been invited to join #{organization_name}"
        end

        def recipient_email
          data[:invited_email]
        end

        def organization_name
          data[:organization_name]
        end

        def inviter_email
          data[:inviter_email]
        end

        def role
          data[:role] || 'member'
        end

        def role_description
          case role
          when 'admin'
            'an administrator'
          else
            'a member'
          end
        end

        def invite_token
          data[:invite_token]
        end

        def invite_uri
          "/invite/#{invite_token}"
        end

        def expires_in_days
          data[:expires_in_days] || DEFAULT_EXPIRY_DAYS
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

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
            invite_uri: invite_uri,
            role_description: role_description,
            expires_in_days: expires_in_days,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end
