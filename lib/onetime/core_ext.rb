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
  def sum ; self.inject(0){|a,x| next if x.nil? || a.nil?; x+a} ; end
  def mean; self.sum.to_f/self.size ; end
  def median
    case self.size % 2
      when 0 then self.sort[self.size/2-1,2].mean
      when 1 then self.sort[self.size/2].to_f
    end if self.size > 0
  end
  def histogram ; self.sort.inject({}){|a,x|a[x]=a[x].to_i+1;a} ; end
  def mode
    map = self.histogram
    max = map.values.max
    map.keys.select{|x|map[x]==max}
  end
  def squares ; self.inject(0){|a,x|x.square+a} ; end
  def variance ; self.squares.to_f/self.size - self.mean.square; end
  def deviation ; Math::sqrt( self.variance ) ; end
  alias_method :sd, :deviation
  def permute ; self.dup.permute! ; end
  def permute!
    (1...self.size).each do |i| ; j=rand(i+1)
      self[i],self[j] = self[j],self[i] if i!=j
    end;self
  end
  def sample n=1 ; (0...n).collect{ self[rand(self.size)] } ; end

  def random
    self[rand(self.size)]
  end
  def percentile(perc)
    self.sort[percentile_index(perc)]
  end
  def percentile_index(perc)
    (perc * self.length).ceil - 1
  end
end
