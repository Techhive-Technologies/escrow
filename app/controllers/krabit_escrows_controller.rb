# frozen_string_literal: true

class Krabit::EscrowsController < ApplicationController
  before_action :ensure_logged_in
  before_action :ensure_escrow_enabled
  before_action :find_escrow, only: %i[show confirm dispute release refund mark_paid]

  # GET /krabit/escrows
  def index
    escrows = KrabitEscrow.for_user(current_user.id)
                          .includes(:buyer, :seller, :topic)
                          .order(created_at: :desc)
                          .limit(50)

    render json: {
      escrows: ActiveModel::ArraySerializer.new(
        escrows,
        each_serializer: KrabitEscrowSerializer,
        scope: current_user
      )
    }
  end

  # GET /krabit/escrows/:id
  def show
    ensure_party_or_admin!
    render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
  end

  # POST /krabit/escrows
  def create
    params.require(:escrow).permit(
      :title, :description, :seller_username,
      :amount, :currency, :topic_id
    )

    seller = User.find_by_username(params[:escrow][:seller_username])
    return render_json_error("Seller not found") unless seller
    return render_json_error("Cannot escrow with yourself") if seller.id == current_user.id

    escrow = KrabitEscrow.new(
      buyer:       current_user,
      seller:      seller,
      title:       params[:escrow][:title],
      description: params[:escrow][:description],
      amount:      params[:escrow][:amount],
      currency:    params[:escrow][:currency] || "USDT",
      topic_id:    params[:escrow][:topic_id]
    )

    if escrow.save
      render json: KrabitEscrowSerializer.new(escrow, scope: current_user, root: false), status: :created
    else
      render_json_error(escrow.errors.full_messages.join(", "))
    end
  end

  # POST /krabit/escrows/:id/mark_paid
  # Called by admin after confirming off-chain payment received
  def mark_paid
    ensure_admin!

    success = @escrow.mark_paid!(
      payment_reference: params.require(:reference),
      payment_method:    params.require(:payment_method),
      confirmed_by:      current_user
    )

    if success
      render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
    else
      render_json_error("Cannot mark as paid in current status: #{@escrow.status}")
    end
  end

  # POST /krabit/escrows/:id/confirm
  # Buyer confirms delivery — funds released to seller
  def confirm
    return render_json_error("Only the buyer can confirm") unless current_user.id == @escrow.buyer_id

    if @escrow.confirm!(by_buyer: current_user)
      render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
    else
      render_json_error("Cannot confirm escrow in current status: #{@escrow.status}")
    end
  end

  # POST /krabit/escrows/:id/dispute
  # Buyer raises a dispute
  def dispute
    return render_json_error("Only the buyer can raise a dispute") unless current_user.id == @escrow.buyer_id

    reason = params[:reason].to_s.strip
    return render_json_error("Please provide a dispute reason") if reason.blank?

    if @escrow.dispute!(by_buyer: current_user, reason: reason)
      render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
    else
      render_json_error("Cannot dispute escrow in current status: #{@escrow.status}")
    end
  end

  # POST /krabit/escrows/:id/release  (admin only)
  def release
    ensure_admin!

    if @escrow.resolve_release!(by_admin: current_user, note: params[:note])
      render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
    else
      render_json_error("Cannot release escrow in current status: #{@escrow.status}")
    end
  end

  # POST /krabit/escrows/:id/refund  (admin only)
  def refund
    ensure_admin!

    if @escrow.resolve_refund!(by_admin: current_user, note: params[:note])
      render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
    else
      render_json_error("Cannot refund escrow in current status: #{@escrow.status}")
    end
  end

  private

  def find_escrow
    @escrow = KrabitEscrow.find_by(id: params[:id])
    return render_json_error("Escrow not found", 404) unless @escrow
  end

  def ensure_party_or_admin!
    return if current_user.admin?
    return if [@escrow.buyer_id, @escrow.seller_id].include?(current_user.id)
    raise Discourse::InvalidAccess
  end

  def ensure_escrow_enabled
    raise Discourse::InvalidAccess unless SiteSetting.krabit_escrow_enabled
  end
end
