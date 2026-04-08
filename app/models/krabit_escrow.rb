# frozen_string_literal: true

class KrabitEscrow < ActiveRecord::Base
  STATUSES   = %w[pending funded delivering completed disputed cancelled declined].freeze
  CURRENCIES = %w[USD NGN USDT USDC].freeze

  belongs_to :buyer,  class_name: "User", foreign_key: :buyer_id
  belongs_to :seller, class_name: "User", foreign_key: :seller_id

  validates :title,    presence: true
  validates :amount,   numericality: { greater_than: 0 }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :status,   inclusion: { in: STATUSES }
  validate  :buyer_and_seller_differ

  before_create :calculate_fees

  scope :for_user, ->(uid) { where("buyer_id = ? OR seller_id = ?", uid, uid) }

  def accept!(by:)
    return false unless status == "pending" && by.id == seller_id
    update!(status: "funded")
    notify_both("Escrow Accepted", "The escrow **#{title}** has been accepted.")
    true
  end

  def decline!(by:)
    return false unless status == "pending" && by.id == seller_id
    update!(status: "declined")
    true
  end

  def mark_delivered!(by:)
    return false unless status == "funded" && by.id == seller_id
    update!(status: "delivering")
    notify(buyer, "Delivery Marked", "**#{title}** has been marked as delivered. Please confirm or dispute.")
    true
  end

  def confirm!(by:)
    return false unless status == "delivering" && by.id == buyer_id
    update!(status: "completed")
    notify_both("Escrow Completed", "**#{title}** is complete. Seller receives #{seller_gets} #{currency}.")
    true
  end

  def dispute!(by:, reason:)
    return false unless status == "delivering" && by.id == buyer_id
    update!(status: "disputed", dispute_reason: reason)
    notify_both("Dispute Raised", "A dispute has been raised for **#{title}**: #{reason}")
    true
  end

  def cancel!(by:)
    return false unless status == "pending" && [buyer_id, seller_id].include?(by.id)
    update!(status: "cancelled")
    true
  end

  private

  def calculate_fees
    fee_pct          = SiteSetting.krabit_escrow_fee_percent.to_d
    self.fee_percent = fee_pct
    self.fee_amount  = (amount * fee_pct / 100).round(2)
    self.seller_gets = (amount - fee_amount).round(2)
  end

  def buyer_and_seller_differ
    errors.add(:seller_id, "can't be the same as buyer") if buyer_id == seller_id
  end

  def notify(user, subject, message)
    PostCreator.create!(
      Discourse.system_user,
      title: subject,
      raw: message,
      archetype: Archetype.private_message,
      target_usernames: [user.username],
      skip_validations: true
    )
  rescue => e
    Rails.logger.error("KrabitEscrow notify failed: #{e.message}")
  end

  def notify_both(subject, message)
    [buyer, seller].each { |u| notify(u, subject, message) }
  end
end
