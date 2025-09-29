module Chat::Ollama
  extend ActiveSupport::Concern

  def complete_with_ollama(content, top_k:, top_p:, &block)
    question = last_question

    context = []

    assistant_response = messages.create(role: "assistant", done: false, content: "", response_number:)

    messages_for_assistant = []
    messages_for_assistant << { role: "system", content: system_prompt }
    messages_for_assistant << messages_hash if messages_hash.any?

    checked_chunks = []

    check_llm = Chat.new_ollama_check_llm

    broadcast_update_to self, :messages,
      target: ActionView::RecordIdentifier.dom_id(assistant_response, :search_content),
      partial: "messages/search_content",
      locals: { message: assistant_response, step: "loading" }

    search_results = Chunk.where(account:).search_by_similarity(question, limit: retrieval_fetch_k)
    search_results.each_with_index do |search_result, index|
      context_to_check = search_result.content

      context_relevance_messages = [
        { role: "system", content: "context_relevance" },
        { role: "user", content: question },
        { role: "context", content: context_to_check }
      ]
      context_relevance_response = check_llm.chat(messages: context_relevance_messages, top_k:, top_p:)

      if context_relevance_response.completion.eql?("No")
        checked_chunks << search_result
      end
    end

    if checked_chunks.any?
      assistant_response.update(similar_chunk_ids: checked_chunks.pluck(:id).uniq)

      context << checked_chunks.map(&:content).join("\n\n")
      context = context.join("\n\n")

      prompt = ENV.fetch("QUERY_PROMPT_TEMPLATE", "Nosia helpful content: {context}\n\n---\n\nNow here is the question you need to answer.\n\nQuestion: {question}")
      prompt = prompt.gsub("{context}", context)
      prompt = prompt.gsub("{question}", question)

      messages_for_assistant.pop
      messages_for_assistant << { role: "user", content: prompt }
    end

    messages_for_assistant = messages_for_assistant.flatten

    llm = Chat.new_ollama_llm
    content_completion = ""
    reasoning_completion = ""
    llm_response = llm.chat(messages: messages_for_assistant, top_k:, top_p:) do |stream|
      if stream && stream["delta"]
        if stream["delta"]["content"].present?
          content_completion << stream["delta"]["content"]
          broadcast_update_to self, :messages,
            target: ActionView::RecordIdentifier.dom_id(assistant_response, :content),
            partial: "messages/content",
            locals: { message: assistant_response, delta: content_completion }
        elsif stream["delta"]["reasoning"].present?
          reasoning_completion << stream["delta"]["reasoning"]
          broadcast_update_to self, :messages,
            target: ActionView::RecordIdentifier.dom_id(assistant_response, :reasoning_content),
            partial: "messages/reasoning_content",
            locals: { message: assistant_response, delta: reasoning_completion }
        end
      end
    end
    assistant_response.update(done: true, content: llm_response.chat_completion, reasoning_content: reasoning_completion)

    answer_relevance_messages = [
      { role: "system", content: "answer_relevance" },
      { role: "user", content: question },
      { role: "assistant", content: llm_response.completion }
    ]

    answer_relevance_response = check_llm.chat(messages: answer_relevance_messages, top_k:, top_p:)
    if answer_relevance_response.completion.eql?("No")
      assistant_response.update(done: true, content: llm_response.completion)
    else
      assistant_response.update(done: true, content: "I don't know.")
    end

    assistant_response
  end
end
