class Prompts
  class << self
    def system_prompt
      all["system_prompt"]
    end

    def context_relevance_guard
      all["context_relevance_guard"]
    end

    def answer_relevance_guard
      all["answer_relevance_guard"]
    end

    def all
      @prompts ||= load_prompts
    end

    private

    def load_prompts
      prompts_path = Rails.root.join("config", "prompts.yml")
      YAML.load_file(prompts_path)
    end
  end
end
