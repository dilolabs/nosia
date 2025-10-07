namespace :embedding_dimensions do
  desc "Change embedding dimensions of existing models"
  task change: :environment do
    # Ask for user confirmation
    puts "This task will change the embedding dimensions of existing models."
    puts "Are you sure you want to proceed? (yes/no)"
    confirmation = STDIN.gets.chomp.downcase
    unless confirmation == "yes"
      puts "Operation cancelled."
      exit
    end

    # Ask for new embedding dimensions
    puts "Enter the new embedding dimension (e.g., 1536):"
    new_dimension = STDIN.gets.chomp.to_i
    if new_dimension <= 0
      puts "Invalid dimension. Operation cancelled."
      exit
    end

    puts "Setting embedding dimension to #{new_dimension}."
    system("EMBEDDING_DIMENSIONS=#{new_dimension} bin/rails db:migrate:redo:primary VERSION=20241216213448")
    puts "Embedding dimension update to #{new_dimension} completed."
  end
end
