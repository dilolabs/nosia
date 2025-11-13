class Author < ApplicationRecord
  has_many :documents, dependent: :nullify

  encrypts :name
end
