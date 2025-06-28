# apps/api/v2/models/mixins/comments.rb

module V2
  module Mixins

    # Model Comments
    #
    module ModelComments

      def self.included(base)
        base.sorted_set :comments # Sorted by time UTC in seconds
      end

      def add_comment(comment)
        comments.add(OT.now.to_i, comment)
      end

      def notes
        comments.rangeraw(0, -1, withscores: true)
      end
    end
  end
end
