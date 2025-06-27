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
      [404, { 'Content-Type' => 'text/plain',
              'Content-Length' => body.size.to_s,
              'X-Cascade' => 'pass' },
       [body]]
    end
  end
end
