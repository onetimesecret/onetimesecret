# lib/onetime/refinements/require_refinements.rb

module Onetime
  module Ruequire
    refine Kernel do
      def require(path)
        return process_rue(path) if path.end_with?('.rue')

        super
      end

      def process_rue(path)
        p "loading RSFC #{path}"
      end
    end
  end
end
