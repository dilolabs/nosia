# frozen_string_literal: true

module Api
  module V1
    class ModelsController < ApplicationController
      def index
        render json: {
          object: "list",
          data: [
            id: ENV["LLM_MODEL"],
            object: "model",
            owned_by: "nosia"
          ]
        }
      end
    end
  end
end
