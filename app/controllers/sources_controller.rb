# frozen_string_literal: true

class SourcesController < ApplicationController
  PAGE_SIZE = 50

  def index
    @type   = normalize(params[:type], SourceRow::TYPES, default: "all")
    @status = normalize(params[:status], SourceRow::STATUSES, default: "all")
    @sort   = normalize(params[:sort], SourceRow::SORTS, default: "recent")
    @query  = params[:q].presence
    @page   = [ params[:page].to_i, 1 ].max
    offset  = (@page - 1) * PAGE_SIZE

    @counts = SourceRow.counts_for(Current.account)
    @total  = SourceRow.total_for(Current.account, type: @type, status: @status, query: @query)
    @rows   = SourceRow.for_account(
      Current.account,
      type: @type, status: @status, query: @query, sort: @sort,
      limit: PAGE_SIZE, offset:
    )
    @has_more = offset + @rows.size < @total

    respond_to do |format|
      format.html
      format.turbo_stream # Load more (added in a later task)
    end
  end

  private
    def normalize(value, allowed, default:)
      allowed.include?(value) ? value : default
    end
end
