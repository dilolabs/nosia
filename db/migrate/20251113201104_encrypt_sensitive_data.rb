class EncryptSensitiveData < ActiveRecord::Migration[8.0]
  def up
    User.find_each(&:encrypt)
    McpServer.find_each(&:encrypt)
    Author.find_each(&:encrypt)
  end

  def down
    User.find_each(&:decrypt)
    McpServer.find_each(&:decrypt)
    Author.find_each(&:decrypt)
  end
end
