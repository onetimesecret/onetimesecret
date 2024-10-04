
module Onetime::App
  module Mail
    MAIL_ERROR = """
    We're experiencing an email delivery issues. You can
    <a href='mailto:problems@onetimesecret.com'>let us know.</a>

    """
    class BaseMailer
      attr_accessor :from, :fromname
      def initialize from, fromname=nil
        @from, @fromname = from, fromname
      end

      def send_email to_address, subject, content
        raise NotImplementedError
      end

      def self.setup
        raise NotImplementedError
      end
    end

  end
end
