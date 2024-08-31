
require 'mustache'

class Onetime::App
  module Mail

    require_relative 'base'

    class Welcome < OT::App::Mail::Base
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

    class SecretLink < OT::App::Mail::Base
      def init secret, recipient
        self[:secret] = secret
        self[:custid] = cust.custid
        self[:email_address] = recipient
        self[:from_name] = OT.conf[:emailer][:fromname]
        self[:from] = OT.conf[:emailer][:from]
        self[:signature_link] = 'https://onetimesecret.com/'
        emailer.fromname = 'Onetime Secret'
      end
      def subject
        i18n[:email][:subject] % [self[:custid]] # e.g. "ABC" sent you a secret
      end
      def display_domain
        secret_display_domain self[:secret]
      end
      def uri_path
        secret_uri self[:secret]
      end
    end

    class PasswordRequest < OT::App::Mail::Base
      def init secret
        self[:secret] = secret
        self[:email_address] = cust.email
      end
      def subject
        "Reset your password (OneTimeSecret.com)"
      end
      def forgot_path
        '/forgot/%s' % self[:secret].key
      end
    end

    class IncomingSupport < OT::App::Mail::Base
      attr_accessor :ticketno
      def init secret, recipient
        self[:secret] = secret
        self[:custid] = cust.custid
        self[:email_address] = recipient
      end
      def subject
        i18n[:email][:subject] % [self[:ticketno]]
      end
      def verify_uri
        secret_uri self[:secret]
      end
    end

    class TestEmail < OT::App::Mail::Base
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
  end
end
