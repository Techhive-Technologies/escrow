# frozen_string_literal: true

class CreateKrabitEscrowTables < ActiveRecord::Migration[7.0]
  def change

    create_table :krabit_escrows do |t|
      # ── Parties ────────────────────────────────────────────────────────
      t.integer  :buyer_id,            null: false
      t.integer  :seller_id,           null: false
      t.integer  :initiator_id,        null: false   # whoever created the escrow
      t.integer  :counterpart_id,      null: false   # whoever needs to accept

      # ── Details ────────────────────────────────────────────────────────
      t.integer  :topic_id                           # optional linked topic
      t.integer  :pm_topic_id                        # auto-created private message
      t.string   :title,               null: false
      t.text     :description
      t.decimal  :amount,              null: false, precision: 18, scale: 8
      t.string   :currency,            null: false, default: "USDT"

      # ── Fees ───────────────────────────────────────────────────────────
      t.decimal  :platform_fee_percent, null: false, precision: 5,  scale: 2, default: 0
      t.decimal  :platform_fee_amount,  null: false, precision: 18, scale: 8, default: 0
      t.decimal  :seller_receives,      null: false, precision: 18, scale: 8, default: 0

      # ── Status ─────────────────────────────────────────────────────────
      # awaiting_acceptance → accepted → paid → delivering
      #   → completed
      #   → disputed → resolved_released | resolved_refunded
      # declined (counterpart declined)
      t.string   :status,              null: false, default: "awaiting_acceptance"

      # ── Timestamps per state ───────────────────────────────────────────
      t.datetime :accepted_at
      t.datetime :declined_at
      t.datetime :paid_at
      t.datetime :delivered_at
      t.datetime :confirmed_at
      t.datetime :disputed_at
      t.datetime :resolved_at
      t.datetime :auto_release_at

      # ── Dispute & resolution ───────────────────────────────────────────
      t.text     :decline_reason
      t.text     :dispute_reason
      t.text     :resolution_note
      t.integer  :resolved_by_id

      # ── Commission flag (for later) ───────────────────────────────────
      t.boolean  :commission_paid,     default: false

      t.timestamps null: false
    end

    add_index :krabit_escrows, :buyer_id
    add_index :krabit_escrows, :seller_id
    add_index :krabit_escrows, :initiator_id
    add_index :krabit_escrows, :counterpart_id
    add_index :krabit_escrows, :status
    add_index :krabit_escrows, :pm_topic_id
    add_index :krabit_escrows, :currency

    create_table :krabit_escrow_payments do |t|
      t.integer  :krabit_escrow_id,  null: false
      t.string   :payment_method,    null: false
      t.decimal  :amount,            null: false, precision: 18, scale: 8
      t.string   :currency,          null: false
      t.string   :status,            null: false, default: "pending"
      t.string   :reference,         null: false
      t.text     :payment_details
      t.integer  :confirmed_by_id
      t.datetime :confirmed_at
      t.timestamps null: false
    end

    add_index :krabit_escrow_payments, :krabit_escrow_id
    add_index :krabit_escrow_payments, :reference, unique: true
    add_index :krabit_escrow_payments, :status
  end
end
