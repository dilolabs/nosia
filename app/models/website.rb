class Website < ApplicationRecord
  include Chunkable
  include Crawlable

  belongs_to :account

  def context
    data
  end

  def title
    return unless data.present?

    document = Commonmarker.parse(data)

    document.walk do |node|
      if node.type == :heading && node.header_level == 1
        return node.first_child.string_content
      end
    end

    nil
  end

  def to_html
    Commonmarker.to_html(data)
  end
end
