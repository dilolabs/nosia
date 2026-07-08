class Website < ApplicationRecord
  include Chunkable
  include Crawlable
  include RobotsCheckable

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
    Commonmarker.to_html(page_body)
  end

  private

  def page_body
    return "" if data.blank?
    return data unless data.start_with?("---\n")

    rest = data[4..]
    close_index = rest.index("\n---\n")
    close_index ? rest[(close_index + 5)..] : data
  end
end
