require_relative 'v2/base'
require_relative '../app_settings'

class Onetime::App
  class APIV2
    include AppSettings
    include Onetime::App::APIV2::Base

    def status
      json status: :nominal, locale: locale
    end

    def version
      json version: OT::VERSION.to_a, locale: locale
    end

  end
end
