module Chat::Completionable
  extend ActiveSupport::Concern

  def complete_with_nosia(question, model: nil, temperature: nil, top_k: nil, top_p: nil, max_tokens: nil, user_message: nil, &block)
    options = default_options.merge(
      {
        model:,
        temperature:,
        top_k:,
        top_p:,
        max_tokens:
      }.compact_blank
    )

    self.assume_model_exists = true
    self.with_model(options[:model], provider: :openai)
    self.with_params(max_tokens: options[:max_tokens], top_p: options[:top_p], top_k: options[:top_k])
    self.with_temperature(options[:temperature])
    self.with_instructions(system_prompt) if messages.empty?

    # Ajouter les tools MCP si disponibles
    mcp_tools_list = mcp_tools
    if mcp_tools_list.any?
      Rails.logger.info "=== Adding #{mcp_tools_list.size} MCP tools to conversation ==="
      self.with_tools(*mcp_tools_list)
    end

    # Si un message utilisateur existe déjà (créé dans le controller), on l'utilise
    # Sinon on en crée un nouveau
    if user_message
      Rails.logger.info "=== Utilisation du message user existant ##{user_message.id} ==="
    else
      Rails.logger.info "=== Création d'un nouveau message user ==="
      user_message = self.messages.create!(role: "user", content: question)
    end

    Rails.logger.info "Messages user avant self.ask: #{self.messages.where(role: 'user').pluck(:id, :content).inspect}"

    # Phase 1: Recherche de contexte
    broadcast_thinking_phase("searching", "Searching through your documents...")
    chunks = self.similarity_search(question)

    # Préparer la question augmentée avec le contexte
    if chunks.any?
      augmented_question = self.augmented_prompt(question, chunks:)
      # Mettre à jour le contenu du message utilisateur avec le contexte
      # MAIS ne pas le broadcaster - on garde juste la question visible
      user_message.update_column(:content, augmented_question)
    end

    # Garder l'ID du message user original
    original_user_message_id = user_message.id

    # Phase 2: Génération de la réponse
    broadcast_thinking_phase("generating", "Generating response...")

    # self.ask() va créer un DEUXIÈME message user, mais il ne sera pas broadcasté
    # grâce à la logique dans broadcast_created qui détecte les doublons
    self.ask(augmented_question || question) do |chunk|
      if block_given?
        yield chunk
      elsif chunk.content && !chunk.content.blank?
        message = self.messages.last
        message.broadcast_append_chunk(chunk.content)
      end
    end

    # Supprimer le message user en doublon créé par self.ask() pour éviter les doublons au rechargement
    # On cherche les messages user créés APRÈS notre message original
    Rails.logger.info "Messages user après self.ask: #{self.messages.where(role: 'user').pluck(:id, :content).inspect}"

    duplicate_user_messages = self.messages
      .where(role: "user")
      .where.not(id: original_user_message_id)
      .where("created_at >= ?", user_message.created_at)

    Rails.logger.info "Doublons potentiels trouvés: #{duplicate_user_messages.pluck(:id).inspect}"

    duplicate_user_messages.each do |duplicate|
      # Vérifier que c'est bien un doublon (même question sans le contexte)
      original_q = user_message.question&.strip
      duplicate_q = duplicate.question&.strip

      Rails.logger.info "Comparaison: original='#{original_q}' vs duplicate='#{duplicate_q}'"

      if original_q == duplicate_q
        Rails.logger.info "✓ Suppression du doublon de message user ##{duplicate.id}"
        duplicate.destroy
      else
        Rails.logger.info "✗ Pas un doublon exact, conservation du message ##{duplicate.id}"
      end
    end

    Rails.logger.info "Messages user finaux: #{self.messages.where(role: 'user').pluck(:id).inspect}"

    message = self.messages.last
    if chunks.any? && !self.answer_relevance(self.messages.last.content, question:)
      message.update(content: "I'm sorry, but I couldn't find relevant information to answer your question based on the provided context.")
    else
      message.update(similar_chunk_ids: chunks.pluck(:id))
    end

    message
  end

  def broadcast_thinking_phase(phase, message)
    broadcast_update_to self, :messages,
      target: "thinking_animation_content",
      partial: "messages/thinking_animation",
      locals: { phase: phase, message: message }
  end

  private

  def default_options
    {
      max_tokens: ENV["LLM_MAX_TOKENS"].to_i,
      model: ENV["LLM_MODEL"],
      temperature: ENV["LLM_TEMPERATURE"].to_f,
      top_k: ENV["LLM_TOP_K"].to_f,
      top_p: ENV["LLM_TOP_P"].to_f
    }
  end

  def retrieval_fetch_k
    ENV["RETRIEVAL_FETCH_K"].to_i
  end

  def system_prompt
    ENV["RAG_SYSTEM_TEMPLATE"]
  end
end
