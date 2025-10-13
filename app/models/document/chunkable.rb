module Document::Chunkable
  extend ActiveSupport::Concern

  included do
    has_many :chunks, as: :chunkable, dependent: :destroy
  end

  def build_chunks
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

    chunks = splitter.chunks(self.content, metadata: self.metadata)
    enriched_chunks = enrich(chunks)

    return enriched_chunks if ActiveModel::Type::Boolean.new.cast(ENV["CHUNK_MERGE_PEERS"]) == false
    merge_peers(enriched_chunks)
  end

  def chunkify!
    new_chunks = build_chunks
    return if new_chunks.empty?

    self.chunks.destroy_all
    self.chunks.create(new_chunks)
  end

  private

  def enrich(chunks)
    enriched_chunks = []

    chunks.each_with_index do |chunk, index|
      enriched_chunks << {
        account_id: self.account_id,
        content: chunk[:text],
        metadata: chunk[:metadata].dup.merge!({
          position: index + 1,
          relative_position: ((index.to_f / chunks.size) * 100).round(1),
          total_chunks: chunks.size,
          total_tokens: estimate_tokens(chunk[:text])
        })
      }
    end

    enriched_chunks
  end

  def estimate_tokens(text)
    text.blank? ? 0 : (text.length / 3.0).ceil
  end

  def merge_chunks(chunk1, chunk2)
    merged_chunk = chunk1.merge(content: [chunk1[:content], chunk2[:content]].join("\n\n"))
    merged_chunk[:metadata][:total_tokens] = chunk1[:metadata][:total_tokens] + chunk2[:metadata][:total_tokens]

    merged_chunk
  end

  def merge_peers(chunks)
    merged_chunks = []
    buffer = nil

    chunks.each do |chunk|
      if buffer.nil?
        buffer = chunk
      elsif (buffer[:metadata][:total_tokens] + chunk[:metadata][:total_tokens]) <= ENV["CHUNK_MAX_TOKENS"].to_i
        buffer = merge_chunks(buffer, chunk)
      else
        merged_chunks << buffer
        buffer = chunk
      end
    end

    merged_chunks << buffer if buffer
  end
end
