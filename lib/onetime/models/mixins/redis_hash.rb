# frozen_string_literal: true


module Onetime::Models
  module RedisHash

    attr_accessor :prefix, :identifier, :suffix, :cache

    def name identifier=nil  # TODO: Rename this method to `rediskey`. Too many collisions on "name".
      self.identifier ||= identifier
      @prefix ||= self.class.to_s.downcase.split('::').last.to_sym
      @suffix ||= :object
      Familia.rediskey prefix, self.identifier, suffix
    end

    def check_identifier!
      if self.identifier.to_s.empty?
        raise RuntimeError, "Identifier cannot be empty for #{self.class}"
      end
    end

    def destroy!
      clear
    end

    def ttl
      ret = (get_value(:ttl) || super).to_i
      ret
    end

    def save
      hsh = { :key => identifier }
      ret = update_fields hsh
      ret == "OK"
    end

    def update_fields hsh={}
      check_identifier!
      hsh[:updated] = OT.now.to_i
      hsh[:created] = OT.now.to_i unless has_key?(:created)
      ret = update hsh
      ## NOTE: caching here like this only works if hsh has all keys
      #self.cache.replace hsh
      ret
    end

    def refresh_cache
      self.cache.replace self.all unless self.identifier.to_s.empty?
    end

    def update_time!
      check_identifier!
      OT.ld "[#{self.class}] Updating time for #{self.identifier}"
      self.put :updated, OT.now.to_i
    end

    def cache
      @cache ||= {}
      @cache
    end

    def short_identifier
      identifier[0,12]
    end

    # Support for accessing ModelBase hash keys via method names.
    # e.g.
    #     s = OT::Session.new
    #     s.agent                 #=> nil
    #     s.agent = "Mozilla..."
    #     s.agent                 #=> "Mozilla..."
    #
    #     s.agent?                # raises NoMethodError
    #
    #     s.agent!                #=> "Mozilla..."
    #     s.agent!                #=> nil
    #
    # NOTA BENE: This will hit the internal cache before redis.
    #
    def method_missing meth, *args
      #OT.ld "Call to #{self.class}###{meth} (cache attempt)"
      last_char = meth.to_s[-1]
      field = case last_char
      when '=', '!', '?'
        meth.to_s[0..-2]
      else
        meth.to_s
      end
      instance_value = instance_variable_get("@#{field}")
      refresh_cache unless !instance_value.nil? || self.cache.has_key?(field)
      ret = case last_char
      when '='
        self[field] = self.cache[field] = args.first.to_s
      when '!'
        self.delete(field) and self.cache.delete(field) # Hash#delete returns the value
      when '?'
        raise NoMethodError, "#{self.class}##{meth.to_s}"
      else
        self.cache[field] || instance_value
      end
      ret
    end

    def get_value field, bypass_cache=false
      self.cache ||= {}
      bypass_cache ? self[field] : (self.cache[field] || self[field])
    end
  end
end
