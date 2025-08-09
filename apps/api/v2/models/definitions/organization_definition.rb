# apps/api/v2/models/definitions/team_definitions.rb

require 'rack/utils'

module V2
  class Organization < Familia::Horreum
    @global = nil

    prefix :org

    class_sorted_set :values

    feature :safe_dump

    identifier_field :orgid

    field :orgid
    field :display_name
    field :description

    hashmap :urls

    def init
      @orgid ||= OT::Utils.generate_short_id
    end
  end
end
