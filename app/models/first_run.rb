class FirstRun
  ACCOUNT_NAME = "Nosia"

  def self.create!(user_params)
    admin = User.create!(user_params.merge(admin: true))

    account = Account.create!(name: ACCOUNT_NAME, owner: admin)
    account.account_users.grant_to admin

    admin
  end
end
