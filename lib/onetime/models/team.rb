# lib/onetime/models/team.rb

require 'rack/utils'

module Onetime
  # Team Model (aka Group)
  #
  class Team < Familia::Horreum

    using Familia::Refinements::TimeLiterals

    feature :safe_dump

    feature :relationships
    feature :object_identifier
    feature :required_fields

    prefix :team

    identifier_field :teamid

    class_sorted_set :values
    sorted_set :members

    field :teamid
    field :display_name
    field :description
    field :owner_id       # custid of team owner

    def init
      @teamid ||= Familia.generate_id
      nil
    end

    # Owner management
    def owner
      Onetime::Customer.load(owner_id) if owner_id
    end

    def owner?(customer)
      customer && customer.custid == owner_id
    end

    # Member management (uses participates_in relationship)
    def add_member(customer, role = 'member')
      # Add to members sorted set with timestamp score (float for Redis sorted sets)
      members.add(customer.objid, Familia.now.to_f)
    end

    def remove_member(customer)
      members.rem(customer.objid)
    end

    def member?(customer)
      return false unless customer
      members.member?(customer.objid)
    end

    def member_count
      members.size
    end

    def list_members
      # Returns Customer objects
      member_ids = members.members
      member_ids.map { |id| Onetime::Customer.load(id) }.compact
    end

    # Authorization helpers
    def can_modify?(current_user)
      owner?(current_user)
    end

    def can_delete?(current_user)
      owner?(current_user)
    end

    class << self
      # Add team to global index
      def add(obj)
        values.add(obj.objid, Familia.now.to_f)
      end

      # Remove team from global index
      def rem(obj)
        values.rem(obj.objid)
      end

      def create!(display_name, owner_customer)
        raise Onetime::Problem, 'Owner required' if owner_customer.nil?
        raise Onetime::Problem, 'Display name required' if display_name.to_s.empty?

        team = new(
          display_name: display_name,
          owner_id: owner_customer.custid
        )
        team.save

        # Add owner as first member
        team.add_member(owner_customer, 'owner')

        OT.ld "[Team.create!] teamid: #{team.teamid}, owner: #{owner_customer.custid}"
        add team
        team
      end
    end
  end
end
