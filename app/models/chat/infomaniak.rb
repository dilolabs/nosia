module Chat::Infomaniak
  extend ActiveSupport::Concern

  class_methods do
    def new_infomaniak_llm(model:)
      Langchain::LLM::OpenAI.new(
        api_key: ENV.fetch("INFOMANIAK_API_KEY", ""),
        llm_options: {
          api_type: :infomaniak,
          uri_base: "https://api.infomaniak.com/1/ai/#{ENV.fetch("INFOMANIAK_PRODUCT_ID", "")}/openai"
        },
        default_options: {
          chat_completion_model_name: model,
          completion_model_name: model,
          embeddings_model_name: ENV.fetch("EMBEDDING_MODEL", "bge_multilingual_gemma2"),
          temperature: ENV.fetch("LLM_TEMPERATURE", 0.1).to_f,
          num_ctx: ENV.fetch("LLM_NUM_CTX", 4_096).to_i
        }
      )
    end
  end

  def complete_with_infomaniak(model:, temperature:, top_p:, max_tokens:, &block)
    question = last_question

    messages_for_assistant = prepare_messages(question)

    assistant_response = messages.create(role: "assistant", done: false, content: "", response_number:)
    assistant_response.broadcast_created

    context = fetch_context(question)
    prompt = generate_prompt(context, question) if context.present?

    messages_for_assistant[-1][:content] = prompt if prompt

    llm = Chat.new_infomaniak_llm(model:)
    llm_response = llm.chat(messages: messages_for_assistant, temperature:, top_p:, max_tokens:, &block)

    assistant_response.update(done: true, content: llm_response.completion)
    assistant_response
  end

  private

  def prepare_messages(question)
    messages = [ { role: "system", content: system_prompt } ]
    messages << messages_hash if messages_hash.any?
    messages.flatten
  end

  def fetch_context(question)
    augmented_context = ActiveModel::Type::Boolean.new.cast(ENV.fetch("AUGMENTED_CONTEXT", false))

    context = account.chunks.similarity_search(question, k: retrieval_fetch_k).map do |retrieved_chunk|
      augmented_context ? retrieved_chunk.augmented_context : retrieved_chunk.context
    end

    context << (augmented_context ? account.augmented_context : account.default_context)

    context.flatten.join("\n\n")
  end

  def generate_prompt(context, question)
    prompt_template = ENV.fetch("QUERY_PROMPT_TEMPLATE", "Nosia helpful content: {context}\n\n---\n\nNow here is the question you need to answer.\n\nQuestion: {question}")
    prompt_template.gsub("{context}", context).gsub("{question}", question)
  end
end
