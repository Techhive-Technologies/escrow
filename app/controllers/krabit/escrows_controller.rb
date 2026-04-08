# frozen_string_literal: true

class Krabit::EscrowsController < ApplicationController
  before_action :ensure_logged_in
  before_action :find_escrow, only: %i[show accept decline mark_delivered confirm dispute cancel]

  def index
    escrows = KrabitEscrow.for_user(current_user.id).includes(:buyer, :seller).order(created_at: :desc)
    render json: { escrows: ActiveModel::ArraySerializer.new(escrows, each_serializer: KrabitEscrowSerializer, scope: current_user) }
  end

  def show
    render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
  end

  def create
    p = params.require(:escrow).permit(:title, :description, :seller_username, :amount, :currency)
    seller = User.find_by_username(p[:seller_username])
    return render_json_error("Seller not found") unless seller
    return render_json_error("Cannot escrow with yourself") if seller.id == current_user.id

    escrow = KrabitEscrow.new(buyer: current_user, seller: seller,
      title: p[:title], description: p[:description], amount: p[:amount], currency: p[:currency] || "USD")

    if escrow.save
      render json: KrabitEscrowSerializer.new(escrow, scope: current_user, root: false), status: :created
    else
      render_json_error(escrow.errors.full_messages.join(", "))
    end
  end

  def accept
    @escrow.accept!(by: current_user) ? ok : render_json_error("Cannot accept")
  end

  def decline
    @escrow.decline!(by: current_user) ? ok : render_json_error("Cannot decline")
  end

  def mark_delivered
    @escrow.mark_delivered!(by: current_user) ? ok : render_json_error("Cannot mark delivered")
  end

  def confirm
    @escrow.confirm!(by: current_user) ? ok : render_json_error("Cannot confirm")
  end

  def dispute
    reason = params[:reason].to_s.strip
    return render_json_error("Reason required") if reason.blank?
    @escrow.dispute!(by: current_user, reason: reason) ? ok : render_json_error("Cannot dispute")
  end

  def cancel
    @escrow.cancel!(by: current_user) ? ok : render_json_error("Cannot cancel")
  end

  private

  def find_escrow
    @escrow = KrabitEscrow.find_by(id: params[:id])
    render_json_error("Not found", 404) unless @escrow
  end

  def ok
    render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
  end
end
