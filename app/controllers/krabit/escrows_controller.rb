# frozen_string_literal: true

module Krabit
  class EscrowsController < ::ApplicationController
    before_action :ensure_logged_in
    before_action :ensure_escrow_enabled
    before_action :ensure_trust_level, only: [:create]
    before_action :find_escrow, only: %i[show accept decline mark_paid mark_delivering confirm dispute release refund]

    # GET /krabit/escrows
    def index
      escrows = KrabitEscrow
                  .for_user(current_user.id)
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
    # Params:
    #   escrow[my_role]             - "buyer" or "seller"
    #   escrow[counterpart_username]- the other party's username
    #   escrow[title]
    #   escrow[description]
    #   escrow[amount]
    #   escrow[currency]
    #   escrow[topic_id]            - optional
    def create
      ep = params.require(:escrow).permit(
        :my_role, :counterpart_username,
        :title, :description,
        :amount, :currency, :topic_id
      )

      my_role = ep[:my_role].to_s
      unless %w[buyer seller].include?(my_role)
        return render_json_error("my_role must be 'buyer' or 'seller'")
      end

      counterpart = User.find_by_username(ep[:counterpart_username])
      return render_json_error("User '#{ep[:counterpart_username]}' not found") unless counterpart
      return render_json_error("You cannot create an escrow with yourself") if counterpart.id == current_user.id

      buyer_user  = my_role == "buyer"  ? current_user : counterpart
      seller_user = my_role == "seller" ? current_user : counterpart

      escrow = KrabitEscrow.new(
        buyer:        buyer_user,
        seller:       seller_user,
        initiator:    current_user,
        counterpart:  counterpart,
        title:        ep[:title],
        description:  ep[:description],
        amount:       ep[:amount],
        currency:     ep[:currency].presence || "USDT",
        topic_id:     ep[:topic_id]
      )

      if escrow.save
        render json: KrabitEscrowSerializer.new(escrow, scope: current_user, root: false), status: :created
      else
        render_json_error(escrow.errors.full_messages.join(", "))
      end
    end

    # POST /krabit/escrows/:id/accept
    def accept
      return render_json_error("Only the counterpart can accept this escrow") unless current_user.id == @escrow.counterpart_id

      if @escrow.accept!(by_user: current_user)
        render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
      else
        render_json_error("Cannot accept escrow in current status: #{@escrow.status}")
      end
    end

    # POST /krabit/escrows/:id/decline
    def decline
      return render_json_error("Only the counterpart can decline this escrow") unless current_user.id == @escrow.counterpart_id

      if @escrow.decline!(by_user: current_user, reason: params[:reason])
        render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
      else
        render_json_error("Cannot decline escrow in current status: #{@escrow.status}")
      end
    end

    # POST /krabit/escrows/:id/mark_paid  (admin only)
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

    # POST /krabit/escrows/:id/mark_delivering
    def mark_delivering
      return render_json_error("Only the seller can mark as delivering") unless current_user.id == @escrow.seller_id

      if @escrow.mark_delivering!(by_user: current_user)
        render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
      else
        render_json_error("Cannot mark as delivering in current status: #{@escrow.status}")
      end
    end

    # POST /krabit/escrows/:id/confirm
    def confirm
      return render_json_error("Only the buyer can confirm") unless current_user.id == @escrow.buyer_id

      if @escrow.confirm!(by_user: current_user)
        render json: KrabitEscrowSerializer.new(@escrow, scope: current_user, root: false)
      else
        render_json_error("Cannot confirm escrow in current status: #{@escrow.status}")
      end
    end

    # POST /krabit/escrows/:id/dispute
    def dispute
      return render_json_error("Only the buyer can raise a dispute") unless current_user.id == @escrow.buyer_id

      reason = params[:reason].to_s.strip
      return render_json_error("Please provide a dispute reason") if reason.blank?

      if @escrow.dispute!(by_user: current_user, reason: reason)
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

    def ensure_trust_level
      min = SiteSetting.krabit_escrow_min_trust_level.to_i
      unless current_user.trust_level >= min
        render_json_error("You must be Trust Level #{min} or above to create an escrow.")
      end
    end
  end
end
