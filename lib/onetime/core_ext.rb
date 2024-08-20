# rubocop:disable all


module QuantizeTime
  def quantize quantum
    stamp = self === Integer ? self : to_i
    Time.at(stamp - (stamp % quantum)).utc
  end
  def on_the_next quantum
    Time.at(quantize(quantum)+quantum).utc
  end
end

module QuantizeInteger
  def quantize quantum
    stamp = self === Integer ? self : to_i
    stamp - (stamp % quantum)
  end
  def on_the_next quantum
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
  def plural(int=1)
    int > 1 || int.zero? ? "#{self}s" : self
  end
  def shorten(len=50)
    return self if size <= len
    self[0..len] + "..."
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
      [404, {"Content-Type" => "text/plain",
         "Content-Length" => body.size.to_s,
         "X-Cascade" => "pass"},
       [body]]
    end
  end
end


class Array
  def sum
    self.compact.inject(0) { |a, x| a + (x.is_a?(Numeric) ? x : 0) }
  end

  def mean
    return 0 if self.empty?
    self.sum.to_f / self.size
  end

  def median
    return nil if self.empty?
    sorted = self.sort
    mid = self.size / 2
    if self.size.even?
      sorted[mid - 1, 2].mean
    else
      sorted[mid].to_f
    end
  end

  def histogram
    self.sort.each_with_object(Hash.new(0)) { |x, a| a[x] += 1 }
  end

  def mode
    map = self.histogram
    max = map.values.max
    map.filter_map { |k, v| k if v == max }
  end

  def squares
    self.filter_map { |x| x.is_a?(Numeric) ? x**2 : nil }.sum
  end

  def variance
    return 0 if self.empty?
    self.squares.to_f / self.size - self.mean**2
  end

  def deviation
    Math.sqrt(self.variance)
  end
  alias_method :sd, :deviation

  def permute
    self.dup.permute!
  end

  def permute!
    (1...self.size).each do |i|
      j = rand(i + 1)
      self[i], self[j] = self[j], self[i] if i != j
    end
    self
  end

  def sample(n = 1)
    Array.new(n) { self[rand(self.size)] }
  end

  def random
    self.sample(1).first
  end

  def percentile(perc)
    self.sort[percentile_index(perc)]
  end

  def percentile_index(perc)
    [(perc * self.length).ceil - 1, 0].max
  end
end
