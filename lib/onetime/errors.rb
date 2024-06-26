

module Onetime

  class Problem < RuntimeError
  end

  class MissingSecret < Problem
  end

  class FormError < Problem
    attr_accessor :form_fields, :message
  end

  class BadShrimp < Problem
    attr_reader :path, :user, :got, :wanted

    def initialize(path, user, got, wanted)
      @path = path
      @user = user
      @got = got.to_s
      @wanted = wanted.to_s
    end

    def report
      "BAD SHRIMP FOR #{@path}: #{@user}: #{got.shorten(16)}/#{wanted.shorten(16)}"
    end

    def message
      'Sorry, bad shrimp'
    end
  end

  class LimitExceeded < RuntimeError
    attr_accessor :event, :message, :cust
    attr_reader :identifier, :event, :count

    def initialize(identifier, event, count)
      @identifier = identifier
      @event = event
      @count = count
    end

    def message
      "[limit-exceeded] #{identifier} for #{event} (#{count})"
    end
  end

  class Unauthorized < RuntimeError
  end

  class Redirect < RuntimeError
    attr_reader :location, :status
    def initialize l, s=302
      @location, @status = l, s
    end
  end

end
