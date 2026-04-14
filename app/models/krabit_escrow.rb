# frozen_string_literal: true

class KrabitEscrow < ActiveRecord::Base
  STATUSES = %w[
    awaiting_acceptance
    accepted
    paid
    delivering
    completed
    disputed
    resolved_released
    resolved_refunded
    declined
  ].freeze

  CURRENCIES = %w[USDT USDC USD_WIRE NGN_BANK].freeze

  belongs_to :buyer,        class_name: "User", foreign_key: :buyer_id
  belongs_to :seller,       class_name: "User", foreign_key: :seller_id
  belongs_to :initiator,    class_name: "User", foreign_key: :initiator_id
  belongs_to :counterpart,  class_name: "User", foreign_key: :counterpart_id
  belongs_to :topic,        optional: true
  belongs_to :pm_topic,     class_name: "Topic", foreign_key: :pm_topic_id, optional: true
  has_many   :payments,     class_name: "KrabitEscrowPayment", foreign_key: :krabit_escrow_id

  validates :buyer_id,    presence: true
  validates :seller_id,   presence: true
  validates :title,       presence: true, length: { maximum: 255 }
  validates :amount,      numericality: { greater_than: 0 }
  validates :currency,    inclusion: { in: CURRENCIES }
  validates :status,      inclusion: { in: STATUSES }
  validate  :buyer_and_seller_must_differ

  before_create :calculate_fees
  after_create  :create_pm_thread

  # ── Scopes ──────────────────────────────────────────────────────────────
  scope :active,    -> { where(status: %w[awaiting_acceptance accepted paid delivering disputed]) }
  scope :completed, -> { where(status: %w[completed resolved_released resolved_refunded declined]) }
  scope :for_user,  ->(user_id) { where("buyer_id = ? OR seller_id = ?", user_id, user_id) }

  # ── State: Accept ────────────────────────────────────────────────────────
  def accept!(by_user:)
    return false unless status == "awaiting_acceptance"
    return false unless by_user.id == counterpart_id

    update!(status: "accepted", accepted_at: Time.current)
    post_to_pm!("✅ **#{by_user.username}** has accepted this escrow. Please proceed with payment.")
    notify_initiator!("escrow_accepted", "#{by_user.username} accepted your escrow request for **#{title}**.")
    true
  end

  # ── State: Decline ───────────────────────────────────────────────────────
  def decline!(by_user:, reason: nil)
    return false unless status == "awaiting_acceptance"
    return false unless by_user.id == counterpart_id

    update!(status: "declined", declined_at: Time.current, decline_reason: reason)
    post_to_pm!("❌ **#{by_user.username}** has declined this escrow request.#{reason.present? ? " Reason: #{reason}" : ""}")
    notify_initiator!("escrow_declined", "#{by_user.username} declined your escrow request for **#{title}**.")
    true
  end

  # ── State: Mark Paid ─────────────────────────────────────────────────────
  def mark_paid!(payment_reference:, payment_method:, confirmed_by:)
    return false unless status == "accepted"

    transaction do
      payments.create!(
        payment_method: payment_method,
        amount:         amount,
        currency:       currency,
        status:         "confirmed",
        reference:      payment_reference,
        confirmed_by_id: confirmed_by.id,
        confirmed_at:   Time.current
      )
      update!(
        status:          "paid",
        paid_at:         Time.current,
        auto_release_at: SiteSetting.krabit_escrow_auto_release_days.days.from_now
      )
    end

    post_to_pm!("💰 Payment of **#{amount} #{currency}** has been confirmed by admin. Seller please proceed with delivery.")
    notify_user!(seller, "escrow_payment_confirmed", "Payment confirmed for escrow **#{title}**. Please proceed with delivery.")
    true
  end

  # ── State: Mark Delivering ───────────────────────────────────────────────
  def mark_delivering!(by_user:)
    return false unless status == "paid"
    return false unless by_user.id == seller_id

    update!(status: "delivering", delivered_at: Time.current)
    post_to_pm!("📦 **#{by_user.username}** has marked this escrow as delivered. Buyer please confirm receipt or raise a dispute.")
    notify_user!(buyer, "escrow_delivered", "Seller has marked **#{title}** as delivered. Please confirm or dispute.")
    true
  end

  # ── State: Confirm ───────────────────────────────────────────────────────
  def confirm!(by_user:)
    return false unless status == "delivering"
    return false unless by_user.id == buyer_id

    update!(status: "completed", confirmed_at: Time.current)
    post_to_pm!("✅ **#{by_user.username}** has confirmed receipt. Escrow completed! Seller will receive **#{seller_receives} #{currency}**.")
    notify_user!(seller, "escrow_completed", "Escrow **#{title}** completed. You will receive #{seller_receives} #{currency}.")
    true
  end

  # ── State: Dispute ───────────────────────────────────────────────────────
  def dispute!(by_user:, reason:)
    return false unless status == "delivering"
    return false unless by_user.id == buyer_id

    update!(status: "disputed", disputed_at: Time.current, dispute_reason: reason)
    post_to_pm!("⚠️ **#{by_user.username}** has raised a dispute.\n\n**Reason:** #{reason}\n\nAn admin will review and resolve this.")
    notify_user!(seller, "escrow_disputed", "Buyer raised a dispute on escrow **#{title}**.")
    true
  end

  # ── State: Resolve Release ───────────────────────────────────────────────
  def resolve_release!(by_admin:, note: nil)
    return false unless status == "disputed"

    update!(
      status:          "resolved_released",
      resolved_at:     Time.current,
      resolved_by_id:  by_admin.id,
      resolution_note: note
    )
    post_to_pm!("🛡️ Admin has resolved this dispute in favour of the **seller**. Funds released.#{note.present? ? "\n\n**Note:** #{note}" : ""}")
    [buyer, seller].each { |u| notify_user!(u, "escrow_resolved", "Dispute on **#{title}** resolved — funds released to seller.") }
    true
  end

  # ── State: Resolve Refund ────────────────────────────────────────────────
  def resolve_refund!(by_admin:, note: nil)
    return false unless status == "disputed"

    update!(
      status:          "resolved_refunded",
      resolved_at:     Time.current,
      resolved_by_id:  by_admin.id,
      resolution_note: note
    )
    post_to_pm!("🛡️ Admin has resolved this dispute in favour of the **buyer**. Funds refunded.#{note.present? ? "\n\n**Note:** #{note}" : ""}")
    [buyer, seller].each { |u| notify_user!(u, "escrow_resolved", "Dispute on **#{title}** resolved — funds refunded to buyer.") }
    true
  end

  # ── Helpers ──────────────────────────────────────────────────────────────
  def active?
    %w[awaiting_acceptance accepted paid delivering disputed].include?(status)
  end

  def completed?
    %w[completed resolved_released resolved_refunded declined].include?(status)
  end

  def display_status
    status.humanize.gsub("_", " ")
  end

  private

  # ── Calculate platform fee on create ─────────────────────────────────────
  def calculate_fees
    fee_pct = SiteSetting.krabit_escrow_platform_fee_percent.to_d
    self.platform_fee_percent = fee_pct
    self.platform_fee_amount  = (amount * fee_pct / 100).round(8)
    self.seller_receives      = (amount - platform_fee_amount).round(8)
  end

  # ── Auto-create private message thread ───────────────────────────────────
  def create_pm_thread
    system_user = Discourse.system_user

    post_creator = PostCreator.new(
      system_user,
      title:         "Escrow ##{id}: #{title}",
      raw:           pm_opening_message,
      archetype:     Archetype.private_message,
      target_usernames: [buyer.username, seller.username].join(","),
      skip_validations: true
    )

    result = post_creator.create

    if result&.topic_id
      update_column(:pm_topic_id, result.topic_id)
    end
  rescue => e
    Rails.logger.error("KrabitEscrow create_pm_thread failed for escrow ##{id}: #{e.message}")
  end

  def pm_opening_message
    <<~MD
      ## 🔒 Escrow Request — #{title}

      | | |
      |---|---|
      | **Buyer** | @#{buyer.username} |
      | **Seller** | @#{seller.username} |
      | **Amount** | #{amount} #{currency} |
      | **Platform Fee** | #{platform_fee_percent}% (#{platform_fee_amount} #{currency}) |
      | **Seller Receives** | #{seller_receives} #{currency} |
      | **Initiated by** | @#{initiator.username} |

      #{description.present? ? "**Description:** #{description}\n\n" : ""}
      ---
      ⏳ This escrow is awaiting acceptance from @#{counterpart.username}.

      Use this thread for all communications related to this transaction.
    MD
  end

  # ── Post a system message to the PM thread ───────────────────────────────
  def post_to_pm!(message)
    return unless pm_topic_id

    PostCreator.create(
      Discourse.system_user,
      topic_id:         pm_topic_id,
      raw:              message,
      skip_validations: true
    )
  rescue => e
    Rails.logger.error("KrabitEscrow post_to_pm! failed for escrow ##{id}: #{e.message}")
  end

  # ── Notifications ─────────────────────────────────────────────────────────
  def notify_initiator!(type, message)
    notify_user!(initiator, type, message)
  end

  def notify_user!(user, type, message)
    user.notifications.create!(
      notification_type: Notification.types[:custom],
      data: { message: message, escrow_id: id }.to_json
    )
  rescue => e
    Rails.logger.error("KrabitEscrow notify_user! failed: #{e.message}")
  end

  def buyer_and_seller_must_differ
    errors.add(:seller_id, "must be different from buyer") if buyer_id == seller_id
  end
end
