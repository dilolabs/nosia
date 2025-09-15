class AddInformationsToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :documents, :keywords, :string
    add_column :documents, :url, :string
    add_column :qnas, :keywords, :string
    add_column :qnas, :title, :string
    add_column :qnas, :url, :string
    add_column :texts, :keywords, :string
    add_column :texts, :title, :string
    add_column :texts, :url, :string
    add_column :websites, :keywords, :string
    add_column :websites, :title, :string
  end
end
