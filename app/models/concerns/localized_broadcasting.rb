module LocalizedBroadcasting
  extend ActiveSupport::Concern

  class_methods do
    # Locale-aware counterpart of the existing broadcasts_to lifecycle macro.
    # @param stream [Proc] Unchanged resource stream parts
    # @return [void]
    def broadcasts_localized_to(stream)
      after_create_commit do
        broadcast_localized_to(:append_later, stream.call(self), target: self.class.broadcast_target_default)
      end
      after_update_commit { broadcast_localized_to(:replace_later, stream.call(self)) }
      after_destroy_commit { broadcast_localized_to(:remove, stream.call(self)) }
    end
  end

  # @param action [Symbol] Existing Turbo action optionally ending _later
  # @param streamables [Array<Object>] Original account/chat/filter parts
  # @param options [Hash] Original rendering/target options
  # @return [void]
  def broadcast_localized_to(action, *streamables, **options)
    I18n.available_locales.each do |locale|
      I18n.with_locale(locale) do
        public_send("broadcast_#{action}_to", *streamables.flatten, locale, **options)
      end
    end
  end
end
