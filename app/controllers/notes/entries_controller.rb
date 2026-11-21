# Opens Notes in the user's current default account, if one is accessible.
class Notes::EntriesController < ApplicationController
  def show
    if (account = Current.user.first_account)
      redirect_to account_notes_workspace_path(account)
    end
  end
end
