

module Familia
  module HorreumRefinements
    refine Familia::Horreum.singleton_class do
      # Converts the class name into a symbol that can be used to look up
      # configuration values. This is particularly useful when mapping
      # database numbers to specific models in the configuration.
      #
      # @example Using in database configuration
      #   # In onetime.rb
      #   def connect_databases
      #     # Config has db numbers like: db_session: 0, db_secret: 1
      #     Onetime::Session.db = OT.conf["db_#{Onetime::Session.to_sym}"]
      #     # => looks up 'db_session' in config
      #   end
      #
      # @return [Symbol] The underscored class name as a symbol
      def to_sym
        name.split('::').last
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
            .to_sym
      end
    end
  end
end
