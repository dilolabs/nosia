# Resolves supported locales from an explicit preference or browser language ranges.
class LanguagePreference
  SUPPORTED = %w[en fr].freeze
  RANGE = /\A\s*([a-z]{1,8}(?:-[a-z0-9]{1,8})*)(?:\s*;\s*q=(0(?:\.\d{0,3})?|1(?:\.0{0,3})?))?\s*\z/i

  class << self
    # @param override [Object] Value from signed preference cookie
    # @param header [String, nil] Accept-Language header
    # @return [Symbol] :en or :fr
    def resolve(override:, header:)
      if explicit?(override)
        override.to_sym
      else
        browser_locale(header)
      end
    end

    # @param value [Object]
    # @return [Boolean] Supported explicit stored locale
    def explicit?(value)
      SUPPORTED.include?(value)
    end

    private
      def browser_locale(header)
        candidates = header.to_s.split(",").each_with_index.filter_map do |range, index|
          match = RANGE.match(range)

          if match
            language = match[1].downcase.split("-").first
            quality = match[2] ? match[2].to_f : 1.0
            [ -quality, index, language.to_sym ] if SUPPORTED.include?(language) && quality.positive?
          end
        end

        candidates.min_by { |quality, index, _language| [ quality, index ] }&.last || :en
      end
  end
end
