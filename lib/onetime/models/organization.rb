# lib/onetime/models/organization.rb

require 'rack/utils'

module Onetime
  # Organization Model
  #
  class Organization < Familia::Horreum

    using Familia::Refinements::TimeLiterals

    prefix :org

    class_sorted_set :values

    feature :safe_dump

    feature :relationships
    feature :object_identifier
    feature :required_fields

    identifier_field :orgid

    field :orgid
    field :display_name
    field :description

    hashkey :urls

    def init
      @orgid ||= Familia.generate_short_id
      nil
    end

    class << self
      def create(display_name = nil, contact_email = nil)
        raise Onetime::Problem, 'Organization exists for that email address' if contact_email && exists?(contact_email)

        org = new display_name: display_name, contact_email: contact_email
        org.save

        OT.ld "[create] orgid: #{org.orgid}, #{org.to_s}"
        add org
        org
      end
    end
  end
end
