# apps/api/v2/models/session/definition.rb

module V2
  class Session < Familia::Horreum

    feature :relatable_object
    feature :safe_dump
    feature :expiration

    ttl 20.minutes
    prefix :session

    class_sorted_set :values, key: 'onetime:session'

    identifier :sessid

    field :ipaddress
    field :custid
    field :useragent
    field :stale
    field :sessid
    field :updated
    field :created
    field :authenticated

    field :shrimp # as string?

    # We check this field in check_referrer! but we rely on this field when
    # receiving a redirect back from Stripe subscription payment workflow.
    field :referrer

    @safe_dump_fields = [
      { identifier: ->(obj) { obj.identifier } },
      :sessid,
      # The external identifier is used by the rate limiter to estimate a unique
      # client. We can't use the session ID b/c the request agent can choose to
      # not send cookies, or the user can clear their cookies (in both cases the
      # session ID would change which would circumvent the rate limiter). The
      # external identifier is now a randomly generated ID that remains consistent
      # for the session lifecycle, providing rate limiting without relying on
      # potentially unreliable data like IP addresses or customer IDs.
      #
      :extid,
      :authenticated,
      :stale,
      :created,
      :updated,
    ].freeze

    # When set to true, the session reports itself as not authenticated
    # regardless of the value of the authenticated field. This allows
    # the site to disable authentication without affecting the session
    # data. For example, if we want to disable authenticated features
    # temporarily (in case of abuse, etc.) we can set this to true so
    # the user will remain signed in after we enable authentication again.
    #
    # During the time that authentication is disabled, the session will
    # be anonymous and the customer will be anonymous.
    #
    # This value is set on every request and should not be persisted.
    #
    attr_accessor :disable_auth

    def init
      # This regular attribute that gets set on each request (if necessary). When
      # true this instance will report authenticated? -> false regardless of what
      # the authenticated field is set to.
      @disable_auth = false if @disable_auth.nil?

      # Don't call the sessid accessor in here. We intentionally allow
      # instantiating a session without a sessid. It's a distinction
      # from create which generates an sessid _and_ saves.
      @sessid ||= nil # rubocop:disable Naming/MemoizedInstanceVariableName
    end


  end
end
