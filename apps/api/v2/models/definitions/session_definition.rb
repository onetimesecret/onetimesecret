# apps/api/v2/models/definitions/session_definition.rb

require_relative '../mixins/session_messages'

module V2
  class Session < Familia::Horreum
    feature :safe_dump
    feature :expiration

    default_expiration 20.minutes
    prefix :session

    class_sorted_set :values, dbkey: 'onetime:session'

    identifier_field :sessid

    field :ipaddress
    field :custid
    field :useragent
    field :stale
    field :sessid, on_conflict: :skip
    field :updated
    field :created
    field :authenticated
    field :external_identifier, on_conflict: :skip

    transient_field :favourite_salad # this will not persist to the database

    field :shrimp # as string?

    # We check this field in check_referrer! but we rely on this field when
    # receiving a redirect back from Stripe subscription payment workflow.
    field :referrer

    @safe_dump_fields = [
      { identifier: ->(obj) { obj.identifier } },
      :sessid,
      :external_identifier,
      :authenticated,
      :stale,
      :created,
      :updated,
    ]

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
      @disable_auth = false

      # Don't call the sessid accessor in here. We intentionally allow
      # instantiating a session without a sessid. It's a distinction
      # from create which generates an sessid _and_ saves.
      @sessid ||= nil # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def save
      @sessid ||= self.class.generate_id
      super
    end

    include V2::Mixins::SessionMessages
  end
end
