# Bounded summaries and private conversation listings for account pages.
module Account::Overview
  extend ActiveSupport::Concern

  class_methods do
    # Counts visible accounts without per-card association queries.
    # @param accounts [Array<Account>] Already-authorized visible directory page
    # @param user [User] The viewer whose private chat counts may be disclosed
    # @return [Hash<Integer, Hash<Symbol, Integer>>]
    def overview_counts_for(accounts, user:)
      ids = accounts.map(&:id)
      counts = ids.index_with { { sources: 0, conversations: 0 } }
      unless ids.empty?
        [ Document, Text, Qna, Website ].each do |model|
          model.where(account_id: ids).group(:account_id).count.each do |account_id, count|
            counts.fetch(account_id)[:sources] += count
          end
        end
        user.chats.root.where(account_id: ids).group(:account_id).count.each do |account_id, count|
          counts.fetch(account_id)[:conversations] = count
        end
      end
      counts
    end
  end

  # @param user [User] The authenticated viewer
  # @return [ActiveRecord::Relation<Chat>] Private root chats, latest activity first
  def conversations_for(user)
    chats.root.where(user: user).order(updated_at: :desc, id: :desc)
  end
end
