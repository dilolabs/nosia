namespace :embeddings do
  desc "Change embedding dimensions of existing models"
  task change_dimensions: :environment do
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

    Rake::Task["embeddings:rebuild"].invoke
  end

  desc "Rebuild all existing embeddings"
  task rebuild: :environment do
    puts "Do you want to rebuild existing embeddings to match the new dimension? (yes/no)"
    rebuild_confirmation = STDIN.gets.chomp.downcase
    if rebuild_confirmation == "yes"
      puts "Rebuilding existing embeddings... (this may take a while)"
      Chunk.find_each(&:generate_embedding!)
      puts "All embeddings have been rebuilt."
    else
      puts "Skipping rebuilding of existing embeddings."
    end
  end
end
