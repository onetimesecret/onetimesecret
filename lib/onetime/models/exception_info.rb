class Onetime::ExceptionInfo < Familia::Horreum
  include Gibbler::Complex

  feature :safe_dump
  feature :expiration

  ttl 30.days
  prefix :exception

  class_sorted_set :values, key: 'onetime:exception'

  identifier :exceptionid

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
    { is_critical: ->(obj) {
      obj.type&.match?(/Fatal|Critical|Emergency/i)
    }},

    # Browser/context info
    { browser_info: ->(obj) {
      agent = obj.user_agent.to_s
      {
        browser: agent.split('/')[0],
        version: agent.split('/')[1],
        mobile: agent.downcase.match?(/mobile|android|iphone/i)
      }
    }},

    # Location info
    { location: ->(obj) {
      return unless obj.url
      uri = URI.parse(obj.url)
      {
        path: uri.path,
        query: uri.query,
        hostname: uri.host
      }
    }},

    # Stack trace processing
    { stack_preview: ->(obj) {
      obj.stack.to_s.split("\n").first(3).join("\n") if obj.stack
    }},
    { stack_length: ->(obj) {
      obj.stack.to_s.split("\n").length if obj.stack
    }}
  ]

  def init
    self.environment ||= 'production'
    self.timestamp ||= Time.now.utc.iso8601
    self.created ||= Time.now.to_i
    self.updated ||= Time.now.to_i
  end

  # Rest of the model code...
end
