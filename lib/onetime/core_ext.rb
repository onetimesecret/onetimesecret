# lib/onetime/core_ext.rb


class String
  def plural(int = 1)
    int > 1 || int.zero? ? "#{self}s" : self
  end

  def shorten(len = 50)
    return self if size <= len

    self[0..len] + '...'
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
