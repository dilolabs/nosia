module AgentSkills
  class DocumentSummarizer < Base
    def call
      chunks = rag_context[:chunks]

      if chunks.empty?
        return { content: "No documents found matching your query.", role: "assistant" }
      end

      by_source = chunks.group_by { |c| c[:source] }
      summaries = by_source.map do |source, source_chunks|
        content = source_chunks.map { |c| c[:content] }.join("\n\n")[0...4000]
        with_instructions(summarization_prompt(source)) do
          ask("Please summarize the following content from source '#{source}':\n\n#{content}")
        end.content
      end

      { content: format_response(summaries, by_source.keys), role: "assistant" }
    end

    private

    def summarization_prompt(source)
      <<~PROMPT
        You are a document summarization assistant. Create a concise summary.
        Focus on: main points, key data, important names, dates, conclusions.
        Use markdown formatting. Source: #{source}
        Respond only with the summary.
      PROMPT
    end

    def format_response(summaries, sources)
      "## Document Summary\n\n#{summaries.join("\n\n---\n\n")}\n\n---\n\n**Sources:** #{sources.join(", ")}"
    end
  end
end
