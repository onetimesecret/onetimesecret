require 'logger'


module V2
  class ExceptionInfo < Familia::Horreum
    include Gibbler::Complex

    feature :safe_dump
    feature :expiration

    ttl 14.days
    prefix :exception

    class_sorted_set :values, key: 'onetime:exception'

    identifier :generate_id

    field :key
    field :message
    field :type
    field :stack
    field :url
    field :line
    field :column
    field :timestamp
    field :user_agent
    field :environment
    field :release
    field :user
    field :created
    field :updated

    @safe_dump_fields = [
      { identifier: ->(obj) { obj.identifier } },
      :message,
      :type,
      :url,
      :line,
      :column,
      :environment,
      :release,
      :user,
      :created,
      :updated,

      # Formatted timestamp for API
      { occurred_at: ->(obj) { obj.timestamp } },

      # Derived fields for API convenience
      { short_id: ->(obj) { obj.identifier.split(':').last } },
      { is_error: ->(obj) { obj.type&.end_with?('Error') } },
      { is_critical: ->(obj) { obj.type&.match?(/Fatal|Critical|Emergency/i) } },

      # Browser/context info
      { browser_info: lambda { |obj|
        agent = obj.user_agent.to_s
        {
          browser: agent.split('/')[0],
          version: agent.split('/')[1],
          mobile: agent.downcase.match?(/mobile|android|iphone/i)
        }
      }},

      # Location info
      { location: lambda { |obj|
        return unless obj.url
        uri = URI.parse(obj.url)
        {
          path: uri.path,
          query: uri.query,
          hostname: uri.host
        }
      }},

      # Stack trace processing
      { stack_preview: lambda { |obj|
        obj.stack.to_s.split("\n").first(3).join("\n") if obj.stack
      }},
      { stack_length: lambda { |obj|
        obj.stack.to_s.split("\n").length if obj.stack
      }},
    ]

    def init
      self.environment ||= 'production'
      self.timestamp ||= Time.now.utc.iso8601
      self.created ||= Time.now.to_i
      self.updated ||= Time.now.to_i
    end

    # Generates and memoizes a unique identifier
    #
    # For historical reasons, we also make sure @key gets set here since
    # Familia::Horreum uses key internally.
    def generate_id
      return @generate_id if defined?(@generate_id)
      @key = Familia.generate_id.slice(0, 31)
      @generate_id = @key
    end

    # Query methods for exception data
    module ClassMethods

      def add(fobj)
        created_time = OT.now.to_i
        identifier = fobj.identifier

        OT.li("[ExceptionInfo] #{identifier} #{fobj.type} #{fobj.release} #{fobj.url}")

        self.values.add(created_time, identifier)

        # Auto-trim the set to keep only the most recent 14 days of feedback
        self.values.remrangebyscore 0, OT.now.to_i-self.ttl # e.g. 14 days
      end

      # Returns a Hash like: {"msg1"=>"1322644672", "msg2"=>"1322644668"}
      def all
        ret = self.values.revrangeraw(0, -1, withscores: true)
        Hash[ret]
      end

      def recent duration=7.days, epoint=OT.now.to_i
        spoint = OT.now.to_i-duration
        ret = self.values.rangebyscoreraw(spoint, epoint, withscores: true)
        Hash[ret]
      end
    end

    extend ClassMethods
  end
end
