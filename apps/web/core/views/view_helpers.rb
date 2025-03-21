# apps/web/core/views/view_helpers.rb

module Core
  module Views
    module ViewHelpers # rubocop:disable Style/Documentation

      def jsvar(value)
        OT::Utils::Sanitation.jsvar(value)
      end

      def jsvars_to_script
        OT::Utils::Sanitation.serialize_to_script(self[:jsvars], id: 'onetime-state', nonce: self[:nonce])
      end

      # Caches the result of a method call for a specified duration.
      #
      # This method is used to cache the result of expensive operations, such as
      # asset generation, in Redis. It provides a simple way to implement caching
      # for view helpers or other frequently called methods.
      #
      # @param methname [String] The name of the method being cached.
      # @yield The block of code to execute if the cache is empty.
      # @return [String] The cached content or the result of the block execution.
      #
      # @example
      #   cached_method('generate_asset') do
      #     # Expensive operation to generate an asset
      #     Asset.generate_complex_asset
      #   end
      #
      # @note The cache key is prefixed with "template:global:" and stored in Redis db 0.
      # @note The default Time To Live (TTL) for the cache is 1 hour.
      #
      def cached_method methname
        rediskey = "template:global:#{methname}"
        cache_object = Familia::String.new rediskey, ttl: 1.hour, db: 0
        OT.ld "[cached_method] #{methname} #{cache_object.exists? ? 'hit' : 'miss'} #{rediskey}"
        cached = cache_object.get
        return cached if cached

        # Existing logic to generate assets...
        content = yield

        # Cache the generated content
        cache_object.set(content)

        content
      end

    end
  end
end
