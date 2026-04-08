class EscrowTransaction < ActiveRecord::Base
  belongs_to :buyer,  class_name: 'User', foreign_key: 'buyer_id'
  belongs_to :seller, class_name: 'User', foreign_key: 'seller_id'

  CURRENCIES = %w[NGN USDT USDC].freeze

  STATUSES = %w[
    pending_acceptance
    accepted
    pending_payment
    funded
    delivered
    completed
    disputed
    resolved
    refunded
    declined
    cancelled
  ].freeze

  CRYPTO_NETWORKS = {
    'USDT' => { 'TRC20' => 'usdttrc20', 'ERC20' => 'usdterc20', 'BEP20' => 'usdtbsc' },
    'USDC' => { 'ERC20' => 'usdcerc20', 'BEP20' => 'usdcbsc' }
  }.freeze

  validates :amount,   numericality: { greater_than: 0 }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :status,   inclusion: { in: STATUSES }

  def crypto?
    %w[USDT USDC].include?(currency)
  end

  def ngn?
    currency == 'NGN'
  end

  def total_with_fee
    amount + fee_amount
  end

  # ── STEP 1: Seller accepts the deal ────────────────────────────────────────
  def accept!
    return false unless status == 'pending_acceptance'
    update!(status: 'accepted', accepted_at: Time.now)
    notify_buyer(:accepted,
      message: I18n.t('escrow.notifications.accepted',
        seller: seller.username, id: id))
    true
  end

  # ── Seller declines the deal ────────────────────────────────────────────────
  def decline!(reason = nil)
    return false unless status == 'pending_acceptance'
    update!(status: 'declined', declined_at: Time.now, decline_reason: reason)
    notify_buyer(:declined,
      message: I18n.t('escrow.notifications.declined',
        seller: seller.username, id: id, reason: reason.to_s))
    true
  end

  # ── STEP 2: Buyer pays — triggered by webhook ───────────────────────────────
  def fund!
    return false unless status == 'pending_payment'
    update!(status: 'funded', funded_at: Time.now)
    notify_seller(:funded,
      message: I18n.t('escrow.notifications.funded',
        amount: amount, currency: currency, buyer: buyer.username, id: id))
    true
  end

  # ── STEP 3: Seller marks as delivered ──────────────────────────────────────
  def deliver!
    return false unless status == 'funded'
    update!(status: 'delivered', delivered_at: Time.now)
    notify_buyer(:delivered,
      message: I18n.t('escrow.notifications.delivered',
        seller: seller.username, id: id))
    true
  end

  # ── STEP 4a: Buyer confirms — releases funds ────────────────────────────────
  def complete!
    return false unless status == 'delivered'
    update!(status: 'completed', completed_at: Time.now)
    notify_seller(:completed,
      message: I18n.t('escrow.notifications.completed',
        amount: amount, currency: currency, id: id))
    true
  end

  # ── STEP 4b: Buyer disputes ─────────────────────────────────────────────────
  def dispute!(raised_by_user_id, reason = nil)
    return false unless %w[funded delivered].include?(status)
    update!(status: 'disputed', disputed_at: Time.now, dispute_reason: reason)
    notify_admins_of_dispute(raised_by_user_id)
    true
  end

  # ── Buyer cancels before paying ─────────────────────────────────────────────
  def cancel!
    return false unless %w[pending_acceptance accepted pending_payment].include?(status)
    update!(status: 'cancelled')
    true
  end

  private

  def notify_buyer(type, message:)
    buyer.notifications.create!(
      notification_type: Notification.types[:custom],
      data: { message: message, url: "/escrow/#{id}" }.to_json
    )
  end

  def notify_seller(type, message:)
    seller.notifications.create!(
      notification_type: Notification.types[:custom],
      data: { message: message, url: "/escrow/#{id}" }.to_json
    )
  end

  def notify_admins_of_dispute(raised_by_id)
    raiser = User.find_by(id: raised_by_id)
    User.where(admin: true).each do |admin|
      admin.notifications.create!(
        notification_type: Notification.types[:custom],
        data: {
          message: "⚠️ Escrow Dispute ##{id} — raised by #{raiser&.username}. Reason: #{dispute_reason}",
          url: "/escrow/#{id}"
        }.to_json
      )
    end
  end
end
