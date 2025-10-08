module Website::Chunkable
  extend ActiveSupport::Concern

  included do
    has_many :chunks, as: :chunkable, dependent: :destroy
  end

  def chunkify!
    separators = [
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
    ]

    splitter = ::Baran::RecursiveCharacterTextSplitter.new(
      chunk_size: ENV["CHUNK_SIZE"].to_i,
      chunk_overlap: ENV["CHUNK_OVERLAP"].to_i,
      separators:,
    )

    new_chunks = splitter.chunks(self.data)

    self.chunks.destroy_all

    new_chunks.each do |new_chunk|
      content = new_chunk.dig(:text)
      next if content.blank?
      self.chunks.create!(account:, content:)
    end
  end
end
