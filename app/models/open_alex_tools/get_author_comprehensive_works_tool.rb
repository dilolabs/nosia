class OpenAlexTools::GetAuthorComprehensiveWorksTool < MCP::Tool
  tool_name "openalex_get_author_comprehensive_works"
  title "Get Author Comprehensive Works"
  description "Search for an author and retrieve all their works in a single comprehensive response"
  
  input_schema(
    properties: {
      author_name: { 
        type: "string", 
        description: "Full name of the author to search for"
      },
      language: { 
        type: "string", 
        description: "Preferred language for response (fr, en, etc.)",
        default: "en"
      }
    },
    required: ["author_name"]
  )
  
  output_schema(
    properties: {
      author_found: { type: "boolean" },
      author_name: { type: "string" },
      author_id: { type: "string" },
      works_count: { type: "integer" },
      cited_by_count: { type: "integer" },
      works: {
        type: "array",
        items: {
          properties: {
            id: { type: "string" },
            doi: { type: "string" },
            title: { type: "string" },
            publication_year: { type: "integer" },
            cited_by_count: { type: "integer" },
            is_open_access: { type: "boolean" }
          }
        }
      },
      message: { type: "string" }
    }
  )
  
  annotations(
    read_only_hint: true,
    destructive_hint: false,
    idempotent_hint: true,
    open_world_hint: false
  )

  def self.call(author_name:, language: "en", server_context:)
    # Step 1: Search for authors
    authors = OpenAlex::Tool.search_authors(author_name)
    
    if authors.empty?
      message = translate("No authors found", language)
      return MCP::Tool::Response.new([{
        type: "text",
        text: message
      }], structured_content: {
        author_found: false,
        message: message
      })
    end
    
    # Step 2: Get works for each author
    all_works = []
    authors.each do |author|
      works = OpenAlex::Tool.get_author_works(author[:id])
      all_works.concat(works)
    end
    
    # Step 3: Format comprehensive response
    first_author = authors.first
    
    response_data = {
      author_found: true,
      author_name: first_author[:name],
      author_id: first_author[:id],
      works_count: first_author[:works_count],
      cited_by_count: first_author[:cited_by_count],
      works: all_works,
      message: format_response_message(authors.length, all_works.length, language)
    }
    
    MCP::Tool::Response.new([{
      type: "text",
      text: response_data[:message]
    }], structured_content: response_data)
  end

  private

  def self.translate(text, language)
    translations = {
      "en" => {
        "No authors found" => "No authors found matching '#{text}'",
        "found_authors" => "Found %d author(s) matching the search",
        "found_works" => "Retrieved %d works across all authors",
        "response_message" => "Found %d author(s) with a total of %d works. Here are the details:"
      },
      "fr" => {
        "No authors found" => "Aucun auteur trouvé correspondant à '%{text}'",
        "found_authors" => "Trouvé %d auteur(s) correspondant à la recherche",
        "found_works" => "Récupéré %d travaux parmi tous les auteurs",
        "response_message" => "Trouvé %d auteur(s) avec un total de %d travaux. Voici les détails :"
      }
    }
    
    translations.dig(language, text) || translations.dig("en", text) || text
  end

  def self.format_response_message(author_count, work_count, language)
    if language == "fr"
      if author_count == 1
        "Trouvé 1 auteur avec #{work_count} travaux. Voici les détails complets :"
      else
        "Trouvé #{author_count} auteurs avec un total de #{work_count} travaux. Voici les détails :"
      end
    else
      if author_count == 1
        "Found 1 author with #{work_count} works. Here are the complete details:"
      else
        "Found #{author_count} authors with a total of #{work_count} works. Here are the details:"
      end
    end
  end
end