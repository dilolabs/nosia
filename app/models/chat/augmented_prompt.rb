module Chat::AugmentedPrompt
  extend ActiveSupport::Concern

  def augmented_prompt(question, chunks:)
    context = chunks.map { |chunk| chunk.context }.join("\n\n")

    "<context>#{context}</context>#{question}"
  end
end
