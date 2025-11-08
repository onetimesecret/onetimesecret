# apps/web/billing/controllers/page.rb

require_relative 'base'

module Billing
  module Controllers
    class Page
      include Controllers::Base

      def index
        view     = Core::Views::VuePoint.new(req, session, cust, locale)
        res.body = view.render
      end

    end
  end
end
