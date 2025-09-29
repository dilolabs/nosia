module Qna::Chunkable
  extend ActiveSupport::Concern

  included do
    has_many :chunks, as: :chunkable, dependent: :destroy
  end

  def chunkify!
    separators = JSON.parse(ENV.fetch("SEPARATORS", [ "\n\n", "\n", " " ]).to_s)

    splitter = ::Baran::RecursiveCharacterTextSplitter.new(
      chunk_size: ENV.fetch("CHUNK_SIZE", 1_500).to_i,
      chunk_overlap: ENV.fetch("CHUNK_OVERLAP", 250).to_i,
      separators:,
    )

    question_and_answer = [ self.question, self.answer ].join("\n\n")

    new_chunks = splitter.chunks(question_and_answer)

    self.chunks.destroy_all

    new_chunks.each do |new_chunk|
      chunk = self.chunks.create!(account:, content: new_chunk.dig(:text))
    end
  end
end
