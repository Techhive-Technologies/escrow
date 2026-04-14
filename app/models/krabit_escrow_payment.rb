# frozen_string_literal: true

class KrabitEscrowPayment < ActiveRecord::Base
  METHODS  = %w[USDT USDC USD_WIRE NGN_BANK].freeze
  STATUSES = %w[pending confirmed failed refunded].freeze

  LABELS = {
    "USDT"     => "USDT (Tether)",
    "USDC"     => "USDC (USD Coin)",
    "USD_WIRE" => "USD Wire Transfer",
    "NGN_BANK" => "NGN Bank Transfer"
  }.freeze

  belongs_to :escrow,       class_name: "KrabitEscrow", foreign_key: :krabit_escrow_id
  belongs_to :confirmed_by, class_name: "User", foreign_key: :confirmed_by_id, optional: true

  validates :payment_method, inclusion: { in: METHODS }
  validates :status,         inclusion: { in: STATUSES }
  validates :reference,      presence: true, uniqueness: true
  validates :amount,         numericality: { greater_than: 0 }

  def label
    LABELS[payment_method] || payment_method
  end

  def parsed_details
    return {} if payment_details.blank?
    JSON.parse(payment_details)
  rescue JSON::ParserError
    {}
  end
end
