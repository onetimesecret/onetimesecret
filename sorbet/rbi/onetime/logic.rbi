# typed: true

module Onetime
  module Logic
    class Base
      extend T::Sig

      sig { returns(T.untyped) }
      attr_reader :sess

      sig { returns(T.untyped) }
      attr_reader :cust

      sig { returns(T.untyped) }
      attr_reader :params

      sig { returns(T.untyped) }
      attr_reader :locale

      sig { returns(T.untyped) }
      attr_reader :processed_params

      sig { returns(T.untyped) }
      attr_reader :plan

      sig { params(sess: T.untyped, cust: T.untyped, params: T.untyped, locale: T.untyped).void }
      def initialize(sess, cust, params = nil, locale = nil); end

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def form_fields; end

      MOBILE_REGEX = T.let(T.untyped, Regexp)
      EMAIL_REGEX = T.let(T.untyped, Regexp)
    end
  end
end
