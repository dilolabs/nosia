module Chunk::Enrichable
  extend ActiveSupport::Concern

  def enrich!
    enrichments = {
      title: generate_title,
      summary: generate_summary,
      keywords: generate_keywords,
      potential_questions: generate_questions
    }

    self.metadata.merge!(enrichments)
    self.save!
  end

  private

  def chat(prompt, instructions: "", max_tokens: 150)
    chat = RubyLLM.chat(model: ENV["LLM_MODEL"], provider: :openai, assume_model_exists: true)
    chat.with_params(max_tokens:)
    chat.with_instructions(instructions)
    response = chat.ask(prompt)
    response.content
  end

  def generate_title
    prompt = "Generate a concise title (max 10 words) for this text:\n\n#{content[0..500]}"
    chat(prompt, instructions: "Generate a concise title (max 10 words) for the text", max_tokens: 20)
  end

  def generate_summary
    prompt = "Summarize this text in 2-3 sentences:\n\n#{content}"
    chat(prompt, instructions: "Summarize the text in 2-3 sentences", max_tokens: 100)
  end

  def generate_keywords
    prompt = "Extract 5-10 important keywords from this text:\n\n#{content[0..500]}"
    response = chat(prompt, instructions: "Extract 5-10 important keywords from the text", max_tokens: 50)
    response.split(/[,\n]/).map(&:strip).reject(&:blank?)
  end

  def generate_questions
    prompt = "Generate 3-5 questions that this text answers:\n\n#{content}"
    response = chat(prompt, instructions: "Generate 3-5 questions that the text answers", max_tokens: 150)
    response.split(/\n/).select { |q| q.strip.end_with?("?") }
  end
end
