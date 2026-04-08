class CreateEscrowTransactions < ActiveRecord::Migration[7.0]
  def change
    create_table :escrow_transactions do |t|
      # Parties
      t.integer  :buyer_id,   null: false
      t.integer  :seller_id,  null: false

      # Deal details
      t.decimal  :amount,      precision: 15, scale: 2, null: false
      t.decimal  :fee_amount,  precision: 15, scale: 2, default: 0
      t.string   :currency,    null: false   # NGN, USDT, USDC
      t.text     :description

      # Status
      # pending_payment → funded → released
      #                          → disputed → resolved / refunded
      #              → cancelled
      t.string   :status, null: false, default: 'pending_payment'

      # Payment tracking
      t.string   :payment_reference   # Paystack ref or NOWPayments payment_id
      t.string   :payment_address     # crypto wallet address shown to buyer
      t.string   :payment_network     # e.g. TRC20, ERC20, BEP20

      # Seller payout info (for NGN)
      t.string   :seller_account_number
      t.string   :seller_bank_code
      t.string   :seller_account_name

      # Timestamps for each stage
      t.datetime :funded_at
      t.datetime :released_at
      t.datetime :disputed_at
      t.datetime :resolved_at

      t.timestamps null: false
    end

    add_index :escrow_transactions, :buyer_id
    add_index :escrow_transactions, :seller_id
    add_index :escrow_transactions, :status
    add_index :escrow_transactions, :payment_reference
  end
end
