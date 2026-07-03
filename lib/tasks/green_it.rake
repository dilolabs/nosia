namespace :green_it do
  desc "Recompute cached token counters on chats and accounts from token_usages (drift repair)"
  task recount: :environment do
    Chat.find_each(&:recount!)
    Account.find_each(&:recount!)
    puts "Recounted token counters."
  end

  desc "Regenerate config/model_energy.yml from the Comparia CSV"
  task import_energy: :environment do
    require "csv"
    rows = CSV.read(Rails.root.join("data/comparia_model-energy-02_07_2026-license_Etalab_2_0.csv"), headers: true)
    out = { "source" => "comparia 2026-07-02, license Etalab-2.0", "models" => {} }
    rows.each do |r|
      conso = r["Consumption mWh (1000 tokens)"]
      next if conso.nil? || conso.to_s.strip == "N/A"
      out["models"][r["id"].to_s.downcase] = conso.to_f
    end
    File.write(Rails.root.join("config", "model_energy.yml"), out.to_yaml)
    puts "Wrote #{out["models"].size} models to config/model_energy.yml"
  end
end
