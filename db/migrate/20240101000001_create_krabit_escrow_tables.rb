# frozen_string_literal: true

class CreateKrabitEscrowTables < ActiveRecord::Migration[7.0]
  def change
    # ── Main escrow table ─────────────────────────────────────────────────
    create_table :krabit_escrows do |t|
      t.integer  :buyer_id,       null: false   # Discourse user ID
      t.integer  :seller_id,      null: false   # Discourse user ID
      t.integer  :topic_id                      # optional link to a topic
      t.string   :title,          null: false
      t.text     :description
      t.decimal  :amount,         null: false, precision: 18, scale: 8
      t.string   :currency,       null: false, default: "USDT"
      t.decimal  :platform_fee_percent, null: false, precision: 5, scale: 2
      t.decimal  :platform_fee_amount,  null: false, precision: 18, scale: 8, default: 0
      t.decimal  :seller_receives,      null: false, precision: 18, scale: 8, default: 0

      # Status flow:
      # pending → paid → delivering → completed
      #                             ↘ disputed → resolved_released
      #                                        → resolved_refunded
      t.string   :status,         null: false, default: "pending"

      t.datetime :paid_at
      t.datetime :delivered_at
      t.datetime :confirmed_at
      t.datetime :disputed_at
      t.datetime :resolved_at
      t.datetime :auto_release_at   # set when paid, auto-release deadline

      t.text     :dispute_reason
      t.text     :resolution_note
      t.integer  :resolved_by_id   # admin user ID

      t.boolean  :invitee_first_escrow, default: false  # for commission tracking later

      t.timestamps null: false
    end

    add_index :krabit_escrows, :buyer_id
    add_index :krabit_escrows, :seller_id
    add_index :krabit_escrows, :topic_id
    add_index :krabit_escrows, :status
    add_index :krabit_escrows, :currency

    # ── Payment records table ─────────────────────────────────────────────
    # Tracks each payment attempt/confirmation for an escrow
    create_table :krabit_escrow_payments do |t|
      t.integer  :krabit_escrow_id, null: false
      t.string   :payment_method,   null: false  # USDT, USDC, USD_WIRE, NGN_BANK
      t.decimal  :amount,           null: false, precision: 18, scale: 8
      t.string   :currency,         null: false
      t.string   :status,           null: false, default: "pending"
                                                 # pending, confirmed, failed, refunded
      t.string   :reference,        null: false  # external tx ID / bank ref
      t.text     :payment_details                # JSON blob for wallet addr, bank info etc
      t.integer  :confirmed_by_id               # admin who confirmed
      t.datetime :confirmed_at

      t.timestamps null: false
    end

    add_index :krabit_escrow_payments, :krabit_escrow_id
    add_index :krabit_escrow_payments, :reference, unique: true
    add_index :krabit_escrow_payments, :status
  end
end
