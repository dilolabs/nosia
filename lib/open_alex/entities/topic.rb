module OpenAlex
  module Entities
    class Topic
      attr_reader :id, :display_name, :domain, :field, :subfield, :works_count

      def initialize(data)
        if data.is_a?(Hash) && data.key?('id')
          @id = data['id']
          @display_name = data['display_name']
          @domain = data['domain']
          @field = data['field']
          @subfield = data['subfield']
          @works_count = data['works_count']
        elsif data.is_a?(Hash) && data[:id]
          @id = data[:id]
          @display_name = nil
          @domain = nil
          @field = nil
          @subfield = nil
          @works_count = nil
        else
          @id = data
          @display_name = nil
          @domain = nil
          @field = nil
          @subfield = nil
          @works_count = nil
        end
      end

      def self.search(name)
        client = OpenAlex::ApiClient.new
        response = client.get("/topics", search: name)
        response['results'].map { |result| new(result) }
      end

      def works
        return [] unless @id && !@id.empty?
        
        client = OpenAlex::ApiClient.new
        response = client.get("/works", filter: "topics.id:#{@id}")
        response['results'].map { |result| OpenAlex::Entities::Work.new(result) }
      end
    end
  end
end