# typed: true

module Onetime
    extend T::Sig

    sig { returns(Symbol) }
    def self.mode
    end

    sig { params(mode: Symbol).void }
    def self.mode=(mode)
    end

    sig { returns(T::Boolean) }
    def self.debug
    end

    sig { params(debug: T::Boolean).void }
    def self.debug=(debug)
    end

    sig { params(guess: T.any(String, Symbol)).returns(T::Boolean) }
    def self.mode?(guess)
    end

    sig { params(name: String).returns(String) }
    def self.errno(name)
    end

    sig { returns(Time) }
    def self.now
    end

    sig { returns(String) }
    def self.entropy
    end
  end

  module Utils
    extend T::Sig

    VALID_CHARS = T.let(['a'..'z', 'A'..'Z', '0'..'9', '*', '$', '!', '?', '(', ')'].flatten, T::Array[String])
    VALID_CHARS_SAFE = T.let(VALID_CHARS - ['i', 'l', 'o', '1', '0'], T::Array[String])

    sig { returns(String) }
    def self.random_fortune
    end

    sig { params(len: Integer, safe: T::Boolean).returns(String) }
    def strand(len = 12, safe = true)
    end

    sig { params(params: T.any(Hash, Array)).returns(T.any(Hash, Array)) }
    def indifferent_params(params)
    end

    sig { returns(Hash) }
    def indifferent_hash
    end

    sig { params(default: Hash, overlay: Hash).returns(Hash) }
    def deep_merge(default, overlay)
    end
  end

  module VERSION
    extend T::Sig

    sig { returns(T::Array[Integer]) }
    def self.to_a
    end

    sig { returns(String) }
    def self.to_s
    end

    sig { returns(String) }
    def self.inspect
    end

    sig { params(msg: T.nilable(String)).returns(Hash) }
    def self.increment!(msg = nil)
    end

    sig { void }
    def self.load_config
    end
  end

  class Plan
    extend T::Sig

    sig { returns(String) }
    attr_reader :planid

    sig { returns(Integer) }
    attr_reader :price

    sig { returns(Float) }
    attr_reader :discount

    sig { returns(Hash) }
    attr_reader :options

    sig { params(planid: String, price: Integer, discount: Float, options: T::Hash[Symbol, T.untyped]).void }
    def initialize(planid, price, discount, options = {})
    end

    sig { returns(Integer) }
    def calculated_price
    end

    sig { returns(T::Boolean) }
    def paid?
    end

    sig { returns(T::Boolean) }
    def free?
    end
  end

  sig { returns(T::Array[String]) }
  def find_configs
  end

  module Entropy
    extend T::Sig

    @values = T.let(Familia::Set.new(name.to_s.downcase.gsub('::', Familia.delim).to_sym, db: 11), Familia::Set)

    sig { returns(Integer) }
    def self.count
    end

    sig { returns(T::Boolean) }
    def self.empty?
    end

    sig { returns(String) }
    def self.pop
    end

    sig { params(count: T.nilable(Integer)).returns(Integer) }
    def self.generate(count = nil)
    end
  end

  module Onetime
    class BaseEmailer
      extend T::Sig

      sig { returns(String) }
      attr_accessor :from

      sig { returns(T.nilable(String)) }
      attr_accessor :fromname

      sig { params(from: String, fromname: T.nilable(String)).void }
      def initialize(from, fromname = nil)
      end

      sig { params(to_address: String, subject: String, content: String).void }
      def send_email(to_address, subject, content)
      end

      sig { void }
      def self.setup
      end
    end
  end
