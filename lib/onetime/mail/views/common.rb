# lib/onetime/mail/views/common.rb

require 'mustache'

require_relative 'base'

module Onetime
  module Mail

    class Welcome < Mail::Views::Base
      def init secret
        self[:secret] = secret
        self[:email_address] = cust.email
      end

      def subject
        i18n[:email][:subject]
      end

      def verify_uri
        secret_uri self[:secret]
      end
    end

    class SecretLink < Mail::Views::Base
      def init secret, recipient
        raise ArgumentError, "Customer required" unless cust
        raise ArgumentError, "Recipient required" unless recipient
        raise ArgumentError, "Secret required" unless secret

        self[:secret] = secret
        self[:custid] = cust.custid
        self[:sender_email] = cust.email
        self[:email_address] = recipient
        self[:from_name] = OT.conf[:emailer][:fromname]
        self[:from] = OT.conf[:emailer][:from]
        self[:signature_link] = baseuri
      end
      def subject
        i18n[:email][:subject] % [self[:sender_email]] # e.g. "ABC" sent you a secret
      end

      def display_domain
        secret_display_domain self[:secret]
      end

      def uri_path
        raise ArgumentError, "Invalid secret key" unless self[:secret]&.key
        secret_uri self[:secret]
      end
    end

    class IncomingSecretNotification < Mail::Views::Base
      def init secret, recipient
        raise ArgumentError, "Secret required" unless secret
        raise ArgumentError, "Recipient required" unless recipient

        self[:secret] = secret
        self[:email_address] = recipient
        self[:from_name] = OT.conf[:emailer][:fromname]
        self[:from] = OT.conf[:emailer][:from]
        self[:signature_link] = baseuri

        # Get memo from metadata if available
        # Load metadata to access memo field
        metadata = V2::Metadata.load(secret.metadata_key) if secret.metadata_key
        self[:memo] = metadata&.memo
        self[:has_passphrase] = metadata&.has_passphrase?
      end

      def subject
        # Security: Don't include memo in subject line as it's visible in email list views
        # The memo is still shown in the email body for context
        "You've received a secret message"
      end

      def display_domain
        secret_display_domain self[:secret]
      end

      def uri_path
        raise ArgumentError, "Invalid secret key" unless self[:secret]&.key
        secret_uri self[:secret]
      end
    end

    class SupportMessage < Mail::Views::Base
      attr_reader :subject
      def init from_name, subject
        @subject = subject
        self[:custid] = cust.custid
        self[:email_address] = cust.custid
        self[:from_name] = from_name
        self[:from] = OT.conf[:emailer][:from]
        self[:signature_link] = baseuri
      end

      def special_fortune
        OT::Utils.random_fortune
      end
    end

    class PasswordRequest < Mail::Views::Base
      def init secret
        self[:secret] = secret
        self[:email_address] = cust.email
      end
      def subject
        "Reset your password (OnetimeSecret.com)"
      end
      def forgot_path
        '/forgot/%s' % self[:secret].key
      end
    end

    class TestEmail < Mail::Views::Base
      def init
        self[:email_address] = cust.email
      end
      def subject
        "This is a test email #{OT.now}"
      end
      def test_variable
        'test_value'
      end
    end

    class FeedbackEmail < Mail::Views::Base
      attr_accessor :message, :display_domain, :domain_strategy
      def init
        self[:email_address] = cust.email
      end
      def subject
        stamp = OT.now.strftime('%b %d, %Y') # in UTC
        "Feedback on #{stamp} via #{display_domain} (#{domain_strategy})"
      end
    end
  end
end
