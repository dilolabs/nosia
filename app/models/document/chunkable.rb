module Document::Chunkable
  extend ActiveSupport::Concern

  included do
    has_many :chunks, as: :chunkable, dependent: :destroy
  end

  def chunkify!
    separators = JSON.parse(ENV.fetch("SEPARATORS", [
      "\n# ", # h1
      "\n## ", # h2
      "\n### ", # h3
      "\n#### ", # h4
      "\n##### ", # h5
      "\n###### ", # h6
      "```\n\n", # code block
      "\n\n***\n\n", # horizontal rule
      "\n\n---\n\n", # horizontal rule
      "\n\n___\n\n", # horizontal rule
      "\n\n", # new line
      "\n", # new line
      " ", # space
      "" # empty
    ].to_s))

    splitter = ::Baran::RecursiveCharacterTextSplitter.new(
      chunk_size: ENV.fetch("CHUNK_SIZE", 1024).to_i,
      chunk_overlap: ENV.fetch("CHUNK_OVERLAP", 64).to_i,
      separators:,
    )

    new_chunks = splitter.chunks(self.content)

    self.chunks.destroy_all

    new_chunks.each do |new_chunk|
      chunk = self.chunks.create!(account:, content: new_chunk.dig(:text))
      sleep(2)
      chunk.vectorize!
    end
  end
end
