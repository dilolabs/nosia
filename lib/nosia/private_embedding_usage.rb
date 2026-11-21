module Nosia
  # Keeps private Note requests out of RubyLLM's non-transactional usage ledger.
  module PrivateEmbeddingUsage
    OWNER = :nosia_private_note_embedding

    # @api private
    def record(entry)
      super unless entry.owner == OWNER
    end
  end
end
