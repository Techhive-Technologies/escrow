# frozen_string_literal: true

class CreateKrabitEscrows < ActiveRecord::Migration[7.0]
  def change
    create_table :krabit_escrows do |t|
      t.integer  :buyer_id,     null: false
      t.integer  :seller_id,    null: false
      t.string   :title,        null: false
      t.text     :description
      t.decimal  :amount,       null: false, precision: 18, scale: 2
      t.string   :currency,     null: false, default: "USD"
      t.decimal  :fee_percent,  null: false, precision: 5,  scale: 2, default: 5.0
      t.decimal  :fee_amount,   null: false, precision: 18, scale: 2, default: 0.0
      t.decimal  :seller_gets,  null: false, precision: 18, scale: 2, default: 0.0
      t.string   :status,       null: false, default: "pending"
      t.text     :dispute_reason
      t.timestamps null: false
    end

    add_index :krabit_escrows, :buyer_id
    add_index :krabit_escrows, :seller_id
    add_index :krabit_escrows, :status
  end
end
