module OpenAlexTools
  def self.all
    [
      SearchWorksTool, GetWorkByDoiTool,
      SearchAuthorsTool, GetAuthorWorksTool, GetAuthorComprehensiveWorksTool,
      SearchSourcesTool, GetSourceWorksTool,
      SearchInstitutionsTool, GetInstitutionWorksTool,
      SearchTopicsTool, GetTopicWorksTool,
      SearchPublishersTool, GetPublisherWorksTool,
      SearchFundersTool, GetFunderWorksTool
    ]
  end
end
