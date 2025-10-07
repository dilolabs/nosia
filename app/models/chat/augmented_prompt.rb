module Chat::AugmentedPrompt
  extend ActiveSupport::Concern

  def augmented_prompt(question, chunks:)
    augmented_context = ActiveModel::Type::Boolean.new.cast(ENV.fetch("AUGMENTED_CONTEXT", false))
    context = chunks.map { |chunk| augmented_context ? chunk.augmented_context : chunk.context }.join("\n\n")

    "<context>#{context}</context>#{question}"
  end
end
