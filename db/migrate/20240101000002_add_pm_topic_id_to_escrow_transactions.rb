class AddPmTopicIdToEscrowTransactions < ActiveRecord::Migration[7.0]
  def change
    add_column :escrow_transactions, :pm_topic_id, :integer
    add_column :escrow_transactions, :title,       :string
  end
end
