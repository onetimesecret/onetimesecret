require 'annoy'
require 'drydock'
require 'onetime'

class OT::CLI < Drydock::Command

  def register_build
    begin
      Onetime::VERSION.increment! argv.first
      puts Onetime::VERSION
    rescue => ex
      puts ex.message
      exit 1
    end
  end
end
