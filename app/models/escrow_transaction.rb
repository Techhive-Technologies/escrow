class EscrowTransaction < ActiveRecord::Base
  belongs_to :buyer,  class_name: 'User', foreign_key: 'buyer_id'
  belongs_to :seller, class_name: 'User', foreign_key: 'seller_id'

  CURRENCIES = %w[NGN USDT USDC].freeze
  STATUSES   = %w[pending_payment funded released disputed resolved refunded cancelled].freeze

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

  def pending?
    status == 'pending_payment'
  end

  def funded?
    status == 'funded'
  end

  # Called when payment is confirmed (by webhook)
  def fund!
    return false unless pending?
    update!(status: 'funded', funded_at: Time.now)
    notify_seller_of_payment
    true
  end

  # Buyer clicks "Release Funds"
  def release!
    return false unless funded?
    update!(status: 'released', released_at: Time.now)
    notify_seller_of_release
    true
  end

  # Either party raises a dispute
  def dispute!(raised_by_user_id)
    return false unless funded?
    update!(status: 'disputed', disputed_at: Time.now)
    notify_admins_of_dispute(raised_by_user_id)
    true
  end

  def total_with_fee
    amount + fee_amount
  end

  private

  def notify_seller_of_payment
    seller.notifications.create!(
      notification_type: Notification.types[:custom],
      data: {
        message: I18n.t('escrow.notifications.funded',
          amount: amount,
          currency: currency,
          buyer: buyer.username
        ),
        url: "/escrow/#{id}"
      }.to_json
    )
  end

  def notify_seller_of_release
    seller.notifications.create!(
      notification_type: Notification.types[:custom],
      data: {
        message: I18n.t('escrow.notifications.released',
          amount: amount,
          currency: currency
        ),
        url: "/escrow/#{id}"
      }.to_json
    )
  end

  def notify_admins_of_dispute(raised_by_id)
    User.where(admin: true).each do |admin|
      admin.notifications.create!(
        notification_type: Notification.types[:custom],
        data: {
          message: "⚠️ Escrow Dispute on transaction ##{id} — raised by user ##{raised_by_id}",
          url: "/escrow/#{id}"
        }.to_json
      )
    end
  end
end
