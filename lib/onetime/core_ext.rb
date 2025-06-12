

module QuantizeTime
  def quantize(quantum)
    stamp = self.is_a?(Integer) ? self : to_i
    Time.at(stamp - (stamp % quantum)).utc
  end

  def on_the_next(quantum)
    Time.at(quantize(quantum)+quantum).utc
  end
end

module QuantizeInteger
  def quantize(quantum)
    stamp = self.is_a?(Integer) ? self : to_i
    stamp - (stamp % quantum)
  end

  def on_the_next(quantum)
    quantize(quantum)+quantum
  end
end

class Time
  include QuantizeTime
end

class Integer
  include QuantizeInteger
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
      [404, {'Content-Type' => 'text/plain',
         'Content-Length' => body.size.to_s,
         'X-Cascade' => 'pass'},
       [body]]
    end
  end
end
