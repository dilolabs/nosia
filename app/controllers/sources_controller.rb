# frozen_string_literal: true

class SourcesController < ApplicationController
  def index
    @documents = Current.account.documents.order(:title)
  end
end
