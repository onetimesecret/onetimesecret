
module Onetime::App
  module Mail

    class BaseMailer
      attr_accessor :from, :fromname, :reply_to

      def initialize(from, fromname, reply_to=nil)
        @from = from
        @fromname = fromname
        @reply_to = reply_to
      end

      def send_email(to_address, subject, html_content, text_content)
        raise NotImplementedError, "Subclasses must implement send_email"
      end

      def self.setup
        raise NotImplementedError
      end
    end

  end
end
