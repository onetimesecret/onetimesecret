# apps/api/v2/models/management/metadata_management.rb

module V2
  class Metadata < Familia::Horreum
    module Management
      def generate_id
        Familia.generate_id
      end
    end

    extend Management
  end
end
