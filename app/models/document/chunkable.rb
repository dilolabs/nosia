module Document::Chunkable
  extend ActiveSupport::Concern

  MAX_TOKENS = ENV["CHUNK_MAX_TOKENS"] ? ENV["CHUNK_MAX_TOKENS"].to_i : 512
  MIN_TOKENS = ENV["CHUNK_MIN_TOKENS"] ? ENV["CHUNK_MIN_TOKENS"].to_i : 128
  MERGE_PEERS = ENV["CHUNK_MERGE_PEERS"] != "false" # Default true

  included do
    has_many :chunks, as: :chunkable, dependent: :destroy
  end

  def chunkify!
    # Phase 1: Split by document structure with full header hierarchy
    structural_chunks = split_by_structure_with_hierarchy(self.content, self.metadata)

    # Phase 2: Split oversized chunks
    token_refined_chunks = split_oversized_chunks(structural_chunks)

    # Phase 3: Merge undersized consecutive chunks
    final_chunks = MERGE_PEERS ? merge_small_chunks(token_refined_chunks) : token_refined_chunks

    chunks = build_enriched_chunks(final_chunks)

    # Replace existing chunks
    self.chunks.destroy_all
    self.chunks.create!(chunks)
  end

  private

  def split_by_structure_with_hierarchy(text, document_metadata)
    chunks = []
    current_chunk = { content: "", metadata: document_metadata.dup }
    header_stack = [] # Track full hierarchy: [{level: 1, text: "Header"}, ...]

    text.each_line do |line|
      if header_match = line.match(/^(#{1-6})\s+(.+)$/)
        # Found a header - save current chunk if it has content
        if current_chunk[:content].strip.present?
          chunks << current_chunk
        end

        level = header_match[1].length
        heading_text = header_match[2].strip

        # Update header stack: remove headers at same or deeper level
        header_stack.reject! { |h| h[:level] >= level }
        header_stack << { level: level, text: heading_text }

        # Build full header path
        header_hierarchy = header_stack.map { |h| h[:text] }

        # Start new chunk
        current_chunk = {
          content: line,
          metadata: document_metadata.merge(
            current_header: heading_text,
            header_level: level,
            header_hierarchy: header_hierarchy.dup,
            section_path: header_hierarchy.join(" > ")
          )
        }
      else
        # Add line to current chunk, maintaining header context
        current_chunk[:content] += line

        # Ensure metadata has current header context even for non-header content
        if header_stack.any?
          current_chunk[:metadata] ||= document_metadata.dup
          current_chunk[:metadata][:header_hierarchy] ||= header_stack.map { |h| h[:text] }
          current_chunk[:metadata][:section_path] ||= header_stack.map { |h| h[:text] }.join(" > ")
        end
      end
    end

    # Add final chunk
    chunks << current_chunk if current_chunk[:content].strip.present?

    chunks
  end

  def split_oversized_chunks(chunks)
    result = []

    chunks.each do |chunk|
      content = chunk[:content]

      # Calculate token count for contextualized version
      contextualized = contextualize_with_metadata(chunk)
      token_count = count_tokens(contextualized)

      if token_count > MAX_TOKENS
        split_parts = split_by_paragraphs_and_tokens(content, chunk[:metadata])
        result.concat(split_parts)
      else
        result << chunk
      end
    end

    result
  end

  def contextualize_with_metadata(chunk)
    headers = chunk[:metadata][:header_hierarchy] || []
    return chunk[:content] if headers.empty?

    headers.join("\n") + "\n" + chunk[:content]
  end

  def split_by_paragraphs_and_tokens(content, metadata)
    parts = split_into_parts(content)
    chunks = []
    current_content = ""
    current_tokens = 0

    # Account for header context in token counting
    header_overhead = count_tokens(metadata[:header_hierarchy]&.join("\n") || "")
    effective_max = MAX_TOKENS - header_overhead

    parts.each do |part|
      part_tokens = count_tokens(part)

      if part_tokens > effective_max
        # Save current accumulated content
        if current_content.present?
          chunks << { content: current_content.strip, metadata: metadata.dup }
          current_content = ""
          current_tokens = 0
        end

        # Split large paragraph by sentences
        sentences = part.split(/(?<=[.!?])\s+/)
        sentences.each do |sentence|
          sentence_tokens = count_tokens(sentence)

          if current_tokens + sentence_tokens > effective_max && current_content.present?
            chunks << { content: current_content.strip, metadata: metadata.dup }
            current_content = sentence + " "
            current_tokens = sentence_tokens
          else
            current_content += sentence + " "
            current_tokens += sentence_tokens
          end
        end
      elsif current_tokens + part_tokens > effective_max
        if current_content.present?
          chunks << { content: current_content.strip, metadata: metadata.dup }
        end
        current_content = part + "\n\n"
        current_tokens = part_tokens
      else
        current_content += part + "\n\n"
        current_tokens += part_tokens
      end
    end

    if current_content.present?
      chunks << { content: current_content.strip, metadata: metadata.dup }
    end

    chunks
  end

  def split_into_parts(content)
    parts = []
    code_block_pattern = /``````/m
    last_index = 0

    content.scan(code_block_pattern).each do |code_block|
      code_index = content.index(code_block, last_index)

      before_text = content[last_index...code_index]
      parts.concat(before_text.split(/\n\s*\n/).reject(&:blank?)) if before_text.present?

      parts << code_block
      last_index = code_index + code_block.length
    end

    remaining_text = content[last_index..]
    parts.concat(remaining_text.split(/\n\s*\n/).reject(&:blank?)) if remaining_text.present?

    parts.map(&:strip).reject(&:blank?)
  end

  def merge_small_chunks(chunks)
    return chunks if chunks.empty?

    merged = []
    current_chunk = chunks.first
    current_tokens = count_tokens(contextualize_with_metadata(current_chunk))

    chunks[1..].each do |chunk|
      chunk_tokens = count_tokens(contextualize_with_metadata(chunk))

      # Only merge if in same section (same header hierarchy)
      same_section = current_chunk[:metadata][:section_path] == chunk[:metadata][:section_path]

      if same_section &&
        (current_tokens < MIN_TOKENS || chunk_tokens < MIN_TOKENS) &&
        (current_tokens + chunk_tokens <= MAX_TOKENS)

        current_chunk[:content] += "\n\n" + chunk[:content]
        current_tokens += chunk_tokens
      else
        merged << current_chunk
        current_chunk = chunk
        current_tokens = chunk_tokens
      end
    end

    merged << current_chunk
    merged
  end

  def count_tokens(text)
    return 0 if text.blank?
    model = BlingFire::Model.new
    model.text_to_words(text).size
  end

  def build_enriched_chunks(chunks)
    chunks.map.with_index do |chunk, index|
      content = chunk[:content]
      metadata = chunk[:metadata] || {}

      {
        account_id: self.account_id,
        content: content,
        metadata: metadata.merge(
          chunk_index: index,
          total_chunks: chunks.size,
          keywords: extract_keywords(content),
          content_type: detect_content_type(content),
          token_count: count_tokens(content)
        )
      }
    end
  end

  # Extract simple keywords from content
  def extract_keywords(content)
    # Remove markdown syntax and code blocks
    clean_text = content.gsub(/``````/, "")
      .gsub(/[#*`\[\]()]/, "")
      .downcase

    # Split into words and filter
    words = clean_text.split(/\W+/)

    # Simple keyword extraction: words longer than 5 chars, excluding common words
    stopwords = %w[about after before between could should would these those through
      during where which while other under above again against their there]

    keywords = words.select { |w| w.length > 5 && !stopwords.include?(w) }
      .tally
      .sort_by { |_, count| -count }
      .first(10)
      .map { |word, _| word }

    keywords.uniq
  end

  # Detect content type for filtering
  def detect_content_type(content)
    types = []
    types << "code" if content.match?(/```/)
    types << "list" if content.match?(/^[\s]*[-*+]\s/m)
    types << "table" if content.match?(/\|.*\|/)
    types << "numbered_list" if content.match?(/^\d+\.\s/m)
    types << "text" if types.empty?

    types
  end
end
