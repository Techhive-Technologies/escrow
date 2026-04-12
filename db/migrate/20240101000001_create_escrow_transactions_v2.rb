class CreateEscrowTransactionsV2 < ActiveRecord::Migration[7.0]
  def change
    create_table :escrow_transactions do |t|
      # Parties
      t.integer  :buyer_id,   null: false
      t.integer  :seller_id,  null: false

      # Deal details
      t.decimal  :amount,      precision: 15, scale: 2, null: false
      t.decimal  :fee_amount,  precision: 15, scale: 2, default: 0
      t.string   :currency,    null: false       # NGN, USDT, USDC
      t.text     :description
      t.text     :decline_reason
      t.text     :dispute_reason

      # Status flow:
      # pending_acceptance → accepted → pending_payment → funded → delivered → completed
      #                    ↘ declined                                         ↘ disputed → resolved/refunded
      t.string   :status, null: false, default: 'pending_acceptance'

      # Payment tracking
      t.string   :payment_reference
      t.string   :payment_address
      t.string   :payment_network     # TRC20, ERC20, BEP20

      # Seller payout info (NGN)
      t.string   :seller_account_number
      t.string   :seller_bank_code
      t.string   :seller_account_name

      # Timestamps for each stage
      t.datetime :accepted_at
      t.datetime :declined_at
      t.datetime :funded_at
      t.datetime :delivered_at
      t.datetime :completed_at
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
