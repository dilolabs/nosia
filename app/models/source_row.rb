# Wraps a source record + its chunk count for the unified Sources list, and
# builds the filtered/sorted/paginated page across the four source types.
# Single-type views run one scoped query; the "all" view merges in memory,
# which is fine at this product's hundreds-scale (see spec §6.3).
class SourceRow
  TYPES  = %w[document text qna website].freeze
  SORTS  = %w[recent title status chunks].freeze
  STATUSES = %w[indexed pending failed].freeze

  attr_reader :record, :chunks_count

  def initialize(record, chunks_count:)
    @record = record
    @chunks_count = chunks_count
  end

  # delegate the interface the view needs
  def id            = record.id
  def to_model      = record
  def source_type_key   = record.source_type_key
  def source_type_label = record.source_type_label
  def display_title = record.display_title
  def source_subtitle = record.source_subtitle
  def index_status  = record.index_status
  def created_at    = record.created_at

  class << self
    def for_account(account, type: "all", status: "all", query: nil, sort: "recent", limit: 50, offset: 0)
      rows = build_rows(account, type:, status:, query:)
      rows = sort_rows(rows, sort)
      rows[offset, limit] || []
    end

    def total_for(account, type: "all", status: "all", query: nil)
      types(type).sum { |t| relation(account, t, status:, query:).count }
    end

    def counts_for(account)
      by_type = TYPES.index_with { |t| account.public_send(t.pluralize).count }
      by_status = STATUSES.index_with do |s|
        TYPES.sum { |t| account.public_send(t.pluralize).where(index_status: s).count }
      end
      { total: by_type.values.sum, by_type:, by_status: }
    end

    private

    def types(type)
      type == "all" ? TYPES : Array(type).select { |t| TYPES.include?(t) }
    end

    def relation(account, type, status:, query:)
      rel = account.public_send(type.pluralize)
      rel = rel.where(index_status: status) if STATUSES.include?(status)
      rel = rel.search(query) if query.present?
      rel
    end

    # Load matching records for every requested type, then attach chunk counts
    # in one grouped query per type (no N+1).
    def build_rows(account, type:, status:, query:)
      types(type).flat_map do |t|
        records = relation(account, t, status:, query:).to_a
        counts  = chunk_counts(account, records.first&.class&.name, records.map(&:id))
        records.map { |r| new(r, chunks_count: counts.fetch(r.id, 0)) }
      end
    end

    def chunk_counts(account, chunkable_type, ids)
      return {} if chunkable_type.nil? || ids.empty?
      account.chunks
        .where(chunkable_type:, chunkable_id: ids)
        .group(:chunkable_id)
        .count
    end

    def sort_rows(rows, sort)
      case sort
      when "title"  then rows.sort_by { |r| r.display_title.to_s.downcase }
      when "status" then rows.sort_by { |r| r.index_status.to_s }
      when "chunks" then rows.sort_by { |r| -r.chunks_count }
      else               rows.sort_by { |r| r.created_at }.reverse # recent
      end
    end
  end
end
