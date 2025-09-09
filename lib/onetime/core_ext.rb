# lib/onetime/core_ext.rb


end

class String
  def plural(int = 1)
    int > 1 || int.zero? ? "#{self}s" : self
  end

  def shorten(len = 50)
    return self if size <= len

    self[0..len] + '...'
  end
end

module Rack
  class Files
    # from: rack 1.2.1
    #
    # Rack::File and Rack::Files are equivalent. Sorbet
    # complains about the constant redefinition for
    # Rack::File.
    #
    # don't print out the literal filename for 404s
    def not_found
      body = "File not found\n"
      [404, { 'content-type' => 'text/plain',
              'Content-Length' => body.size.to_s,
              'X-Cascade' => 'pass' },
       [body]]
    end
  end
end

# Fix for Mustache 1.1.1 generator compatibility. There is
# no Mustache::VERSION to check the version. The most
# recent release was in 2015 so I think we'll be okay.
if defined?(Mustache)
  require 'mustache'

  module MustacheGeneratorFix
    private

    def compile!(exp)
      case exp.first
      when :multi
        exp[1..].reduce(+'') { |sum, e| sum << compile!(e) }
      when :static
        str(exp[1])
      when :mustache
        send("on_#{exp[1]}", *exp[2..])
      else
        raise "Unhandled exp: #{exp.first}"
      end
    end
  end

  Mustache::Generator.prepend(MustacheGeneratorFix)
end
