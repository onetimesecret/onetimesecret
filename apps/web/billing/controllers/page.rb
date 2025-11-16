# apps/web/billing/controllers/page.rb
#
# frozen_string_literal: true

require_relative 'base'

module Billing
  module Controllers
    class Page
      include Controllers::Base

      def index
        view     = Core::Views::VuePoint.new(req)
        res.body = view.render
      end
    end
  end
end
