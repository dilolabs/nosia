# lib/engines/registry.rb
require_relative "registration"

module Engines
  module Registry
    class DuplicateIdError < StandardError; end

    @registrations = {}

    class << self
      def register(registration)
        if @registrations.key?(registration.id)
          raise DuplicateIdError, "Engine already registered: #{registration.id}"
        end

        @registrations[registration.id] = registration
      end

      def all
        @registrations.values
      end

      def find(id)
        @registrations[id.to_s]
      end
      alias_method :[], :find

      def clear
        @registrations.clear
      end
    end
  end
end
