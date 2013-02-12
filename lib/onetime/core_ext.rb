#encoding: utf-8
$KCODE = "u" if RUBY_VERSION =~ /^1.8/

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
class Fixnum
  include QuantizeInteger
end


unless defined?(Time::Units)
  class Time
    module Units
      PER_MICROSECOND = 0.000001.freeze
      PER_MILLISECOND = 0.001.freeze
      PER_MINUTE = 60.0.freeze
      PER_HOUR = 3600.0.freeze
      PER_DAY = 86400.0.freeze

      def microseconds()    seconds * PER_MICROSECOND     end
      def milliseconds()    seconds * PER_MILLISECOND    end
      def seconds()         self                         end
      def minutes()         seconds * PER_MINUTE          end
      def hours()           seconds * PER_HOUR             end
      def days()            seconds * PER_DAY               end
      def weeks()           seconds * PER_DAY * 7           end
      def years()           seconds * PER_DAY * 365        end

      def in_years()        seconds / PER_DAY / 365      end
      def in_weeks()        seconds / PER_DAY / 7       end
      def in_days()         seconds / PER_DAY          end
      def in_hours()        seconds / PER_HOUR          end
      def in_minutes()      seconds / PER_MINUTE         end
      def in_milliseconds() seconds / PER_MILLISECOND    end
      def in_microseconds() seconds / PER_MICROSECOND   end

      def in_time
        Time.at(self).utc
      end

      def in_seconds(u=nil)
        case u.to_s
        when /\A(y)|(years?)\z/
          years
        when /\A(w)|(weeks?)\z/
          weeks
        when /\A(d)|(days?)\z/
          days
        when /\A(h)|(hours?)\z/
          hours
        when /\A(m)|(minutes?)\z/
          minutes
        when /\A(ms)|(milliseconds?)\z/
          milliseconds
        when /\A(us)|(microseconds?)|(μs)\z/
          microseconds
        else
          self
        end
      end


      ## JRuby doesn't like using instance_methods.select here.
      ## It could be a bug or something quirky with Attic
      ## (although it works in 1.8 and 1.9). The error:
      ##
      ##  lib/attic.rb:32:in `select': yield called out of block (LocalJumpError)
      ##  lib/stella/mixins/numeric.rb:24
      ##
      ## Create singular methods, like hour and day.
      # instance_methods.select.each do |plural|
      #   singular = plural.to_s.chop
      #   alias_method singular, plural
      # end

      alias_method :ms, :milliseconds
      alias_method :'μs', :microseconds
      alias_method :second, :seconds
      alias_method :minute, :minutes
      alias_method :hour, :hours
      alias_method :day, :days
      alias_method :week, :weeks
      alias_method :year, :years

    end
  end

  class Numeric
    include Time::Units

    def to_ms
      (self*1000.to_f)
    end

    # TODO: Use 1024?
    def to_bytes
      args = case self.abs.to_i
      when (1000)..(1000**2)
        '%3d%s' % [(self / 1000.to_f), 'KB']
      when (1000**2)..(1000**3)
        '%3df%s' % [(self / (1000**2).to_f), 'MB']
      when (1000**3)..(1000**4)
        '%3d%s' % [(self / (1000**3).to_f), 'GB']
      when (1000**4)..(1000**6)
        '%3d%s' % [(self / (1000**4).to_f), 'TB']
      else
        [self.to_i, 'B'].join
      end
    end
  end
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
  class File
    # from: rack 1.2.1
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

class Numeric
  def square ; self * self ; end
  def fineround(len=6.0)
    v = (self * (10.0**len)).round / (10.0**len)
    v.zero? ? 0 : v
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




# Since rack 1.4, Rack::Reloader doesn't actually reload.
# A new instance is created for every request, so the cached
# modified times are reset every time.
# This patch uses a class variable for the @mtimes hash
# instead of an instance variable.
module Rack
  class Reloader
    @mtimes = {}
    class << self
      attr_reader :mtimes
    end
    def reload!(stderr = $stderr)
      rotation do |file, mtime|
        previous_mtime = self.class.mtimes[file] ||= mtime
        safe_load(file, mtime, stderr) if mtime > previous_mtime
      end
    end
    def safe_load(file, mtime, stderr = $stderr)
      load(file)
      stderr.puts "#{self.class}: reloaded `#{file}'"
      file
    rescue LoadError, SyntaxError => ex
      stderr.puts ex
    ensure
      self.class.mtimes[file] = mtime
    end
  end
end
