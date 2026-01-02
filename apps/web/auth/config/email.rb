# apps/web/auth/config/email.rb
#
# frozen_string_literal: true

require 'onetime/mail'
require_relative '../../../../lib/onetime/jobs/publisher'

module Auth::Config::Email
  def self.configure(auth)
    # Configure Rodauth email settings
    auth.email_from Onetime::Mail::Mailer.from_address
    auth.email_subject_prefix ''  # Templates handle their own prefixes

    # ========================================================================
    # EMAIL TEMPLATES - Integrate with Onetime::Mail::Templates
    # ========================================================================

    # Verify Account Email (sent during account creation)
    # Full mode: use Rodauth's verification URL (/verify-account?key=...)
    auth.create_verify_account_email do
      template = Onetime::Mail::Templates::Welcome.new({
        email_address: email_to,
        verification_path: verify_account_email_link,
        baseuri: request.base_url,
        product_name: OT.conf.dig('site', 'product_name'),
        display_domain: request.host,
      }, locale: determine_account_locale
                                                      )

      build_multipart_email(template)
    end

    # Reset Password Email (sent when user requests password reset)
    auth.create_reset_password_email do
      template = Onetime::Mail::Templates::PasswordRequest.new({
        email_address: email_to,
        secret: reset_password_key_value,
        baseuri: request.base_url,
        product_name: OT.conf.dig('site', 'product_name'),
        display_domain: request.host,
      }, locale: determine_account_locale
                                                              )

      build_multipart_email(template)
    end

    # ========================================================================
    # EMAIL DELIVERY - Unified mailer with RabbitMQ/sync fallback
    # ========================================================================

    # Configure email delivery using unified mailer
    auth.send_email do |email|
      Onetime.auth_logger.debug 'send_email hook called', {
        subject: email.subject.to_s,
        to: email.to.to_s,
        multipart: email.multipart?,
        rack_env: ENV.fetch('RACK_ENV', nil),
      }

      # Extract body content from multipart or simple email
      body_content = if email.multipart?
                       # For multipart, prefer text part for plain email delivery
                       # (Our mailer will send the plain text version)
                       email.text_part&.body&.decoded || email.body.to_s
                     else
                       email.body.to_s
                     end

      # Critical auth flow (verification, password reset): use sync fallback
      # Rodauth emails must be delivered - user is waiting for auth action
      Onetime::Jobs::Publisher.enqueue_email_raw({
        to: email.to,
        from: email.from,
        subject: email.subject,
        body: body_content,
      }, fallback: :sync
                                                )
    end

    # ========================================================================
    # HELPER METHODS
    # ========================================================================

    # Determine locale for current account/session
    # Priority: account preference > session > request param > default
    auth.auth_class_eval do
      def determine_account_locale
        account[:locale] ||
          session[:locale] ||
          request.params['locale'] ||
          I18n.default_locale.to_s
      end

      # Build multipart email (text + HTML) from template
      # @param template [Onetime::Mail::Templates::Base] Template instance
      # @return [Mail::Message] Multipart email message
      def build_multipart_email(template)
        html_body = template.render_html

        # If no HTML version, use simple text email
        return create_email(template.subject, template.render_text) unless html_body

        # Create multipart email with text and HTML versions
        # Rodauth's create_email signature: create_email(subject, body)
        mail = create_email(template.subject, '')

        # Add text part
        mail.text_part = Mail::Part.new do
          body template.render_text
        end

        # Add HTML part
        mail.html_part = Mail::Part.new do
          content_type 'text/html; charset=UTF-8'
          body html_body
        end

        mail
      end
    end

    OT.info '[email] Email templates and delivery configured'
  end
end
