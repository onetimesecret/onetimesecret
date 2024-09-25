
module Onetime
  class App::Data

    class Info
      include Onetime::App::Base
      def privacy
        publically do
          view = Onetime::App::Views::Info::Privacy.new req, sess, cust, locale
          res.body = view.render
        end
      end
      def security
        publically do
          view = Onetime::App::Views::Info::Security.new req, sess, cust, locale
          res.body = view.render
        end
      end
      def terms
        publically do
          view = Onetime::App::Views::Info::Terms.new req, sess, cust, locale
          res.body = view.render
        end
      end
    end

  end
end
