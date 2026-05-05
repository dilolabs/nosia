module OpenAlex
  module Entities
    class Source
      attr_reader :id, :display_name, :publisher, :issn, :works_count, :cited_by_count

      def initialize(data)
        if data.is_a?(Hash) && data.key?('id')
          @id = data['id']
          @display_name = data['display_name']
          @publisher = data['publisher']
          @issn = data['issn']
          @works_count = data['works_count']
          @cited_by_count = data['cited_by_count']
        elsif data.is_a?(Hash) && data[:id]
          @id = data[:id]
          @display_name = nil
          @publisher = nil
          @issn = nil
          @works_count = nil
          @cited_by_count = nil
        else
          @id = data
          @display_name = nil
          @publisher = nil
          @issn = nil
          @works_count = nil
          @cited_by_count = nil
        end
      end

      def self.search(name)
        client = OpenAlex::ApiClient.new
        response = client.get("/sources", search: name)
        response['results'].map { |result| new(result) }
      end

      def self.find_by_issn(issn)
        client = OpenAlex::ApiClient.new
        response = client.get("/sources", filter: "issn:#{issn}")
        new(response['results'].first) if response['results'].any?
      end

      def works
        return [] unless @id && !@id.empty?
        
        client = OpenAlex::ApiClient.new
        response = client.get("/works", filter: "primary_location.source.id:#{@id}")
        response['results'].map { |result| OpenAlex::Entities::Work.new(result) }
      end
    end
  end
end