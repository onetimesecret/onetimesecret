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

    # Familia v2 relationships - Team has members collection
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

    # Member management - manual relationship (Familia v2 sorted_set)
    # Note: Without participates_in, add_member must be defined manually

    def add_member(customer, role = 'member')
      members.add(customer.objid, Familia.now.to_f)
    end

    def remove_member(customer)
      members.remove(customer.objid)
    end

    def member?(customer)
      return false unless customer
      members.member?(customer.objid)
    end

    def member_count
      members.size
    end

    def list_members
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
      def create!(display_name, owner_customer)
        raise Onetime::Problem, 'Owner required' if owner_customer.nil?
        display_name = display_name.to_s.strip
        raise Onetime::Problem, 'Display name required' if display_name.empty?

        team = new(
          display_name: display_name,
          owner_id: owner_customer.custid
        )
        team.save

        # Add owner as first member using Familia v2 relationship
        team.add_member(owner_customer)

        OT.ld "[Team.create!] teamid: #{team.teamid}, owner: #{owner_customer.custid}"
        # Familia v2 automatically manages instances collection - no manual add needed
        team
      end
    end
  end
end
