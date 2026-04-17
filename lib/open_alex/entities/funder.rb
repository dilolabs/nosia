module OpenAlex
  module Entities
    class Funder
      attr_reader :id, :display_name, :works_count, :cited_by_count

      def initialize(data)
        if data.is_a?(Hash) && data.key?('id')
          @id = data['id']
          @display_name = data['display_name']
          @works_count = data['works_count']
          @cited_by_count = data['cited_by_count']
        elsif data.is_a?(Hash) && data[:id]
          @id = data[:id]
          @display_name = nil
          @works_count = nil
          @cited_by_count = nil
        else
          @id = data
          @display_name = nil
          @works_count = nil
          @cited_by_count = nil
        end
      end

      def self.search(name)
        client = OpenAlex::ApiClient.new
        response = client.get("/funders", search: name)
        response['results'].map { |result| new(result) }
      end

      def works
        return [] unless @id && !@id.empty?
        
        client = OpenAlex::ApiClient.new
        response = client.get("/works", filter: "funders.id:#{@id}")
        response['results'].map { |result| OpenAlex::Entities::Work.new(result) }
      end
    end
  end
end