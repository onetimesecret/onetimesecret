require_relative 'v2/base'
require_relative '../base'  # app/base.rb

class Onetime::App
  class API2
    include AppSettings
    include Onetime::App::API2::Base

    def status
      json status: :nominal, locale: locale
    end

    def version
      json version: OT::VERSION.to_a, locale: locale
    end

  end
end
