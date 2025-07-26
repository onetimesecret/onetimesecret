# lib/onetime/refinements/horreum_refinements.rb

module Familia
  # Temporary workarounds for Familia::Horreum models in
  # between Familia releases. TODO: Move to familia
  module HorreumRefinements
    refine Familia::Horreum.singleton_class do
      # Converts the class name into a string that can be used to look up
      # configuration values. This is particularly useful when mapping
      # familia models with specific database numbers in the configuration.
      #
      # @example V2::Session.config_name => 'session'
      #
      # @return [String] The underscored class name as a string
      def config_name
        name.split('::').last
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end

    end
  end
end
