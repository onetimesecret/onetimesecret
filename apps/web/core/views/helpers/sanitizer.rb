# apps/web/core/views/helpers/sanitizer.rb

module Core
  module Views
    module SanitizerHelpers # rubocop:disable Style/Documentation

      def normalize_value(value)
        Onetime::Utils::Sanitation.normalize_value(value)
      end

      def serialized_to_script
        data = serialized_data
        nonce = global_vars[:nonce]
        to_json_script(data, id: 'onetime-state', nonce: nonce)
      end

      # Collects data and returns a script tag for embedding.
      def to_json_script(data, id: nil, nonce: nil)
        sanitized_json = to_sanitized_json(data)
        attributes = ['type="application/json"']
        attributes << %{id="#{Rack::Utils.escape_html(id)}"} if id
        attributes << %{nonce="#{nonce}"} if nonce

        "<script #{attributes.join(' ')}>#{sanitized_json}</script>"
      end

      # Converts data to JSON and sanitizes it to reduce risk of injection attacks.
      # Escapes certain special characters and script tags.
      def to_sanitized_json(data)
        data.to_json
          .gsub(%r{</script}i, '<\/script')
          .gsub(/[\u0000-\u001F]/, '')
          .gsub(/[^\x20-\x7E]/) { |c| "\\u#{c.ord.to_s(16).rjust(4, '0')}" }
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
