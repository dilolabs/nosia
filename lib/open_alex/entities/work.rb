module OpenAlex
  module Entities
    class Work
      attr_reader :id, :doi, :title, :publication_year, :cited_by_count, :is_oa

      def initialize(data)
        @id = data['id']
        @doi = data['doi']
        @title = data['title']
        @publication_year = data['publication_year']
        @cited_by_count = data['cited_by_count']
        @is_oa = data['is_oa']
      end

      def self.find_by_doi(doi)
        client = OpenAlex::ApiClient.new
        response = client.get("/works", filter: "doi:#{doi}")
        new(response['results'].first) if response['results'].any?
      end
    end
  end
end