
module Onetime::App
  module Mail

    class BaseMailer
      attr_accessor :reply_to
      attr_reader :from, :fromname

      def initialize(from, fromname, reply_to=nil)
        OT.ld "[mail-init] from:#{from}, fromname:#{fromname}, reply-to:#{reply_to}"
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
