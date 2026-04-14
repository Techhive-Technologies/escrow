# frozen_string_literal: true

class KrabitEscrowSerializer < ApplicationSerializer
  attributes :id,
             :title,
             :description,
             :amount,
             :currency,
             :platform_fee_percent,
             :platform_fee_amount,
             :seller_receives,
             :status,
             :display_status,
             :topic_id,
             :pm_topic_id,
             :paid_at,
             :accepted_at,
             :declined_at,
             :delivered_at,
             :confirmed_at,
             :disputed_at,
             :resolved_at,
             :auto_release_at,
             :decline_reason,
             :dispute_reason,
             :resolution_note,
             :created_at,
             # Permission flags for the frontend
             :can_accept,
             :can_decline,
             :can_mark_delivering,
             :can_confirm,
             :can_dispute,
             :is_initiator,
             :my_role,
             :buyer,
             :seller

  def buyer
    BasicUserSerializer.new(object.buyer, root: false)
  end

  def seller
    BasicUserSerializer.new(object.seller, root: false)
  end

  def can_accept
    scope&.id == object.counterpart_id && object.status == "awaiting_acceptance"
  end

  def can_decline
    scope&.id == object.counterpart_id && object.status == "awaiting_acceptance"
  end

  def can_mark_delivering
    scope&.id == object.seller_id && object.status == "paid"
  end

  def can_confirm
    scope&.id == object.buyer_id && object.status == "delivering"
  end

  def can_dispute
    scope&.id == object.buyer_id && object.status == "delivering"
  end

  def is_initiator
    scope&.id == object.initiator_id
  end

  def my_role
    return "buyer"  if scope&.id == object.buyer_id
    return "seller" if scope&.id == object.seller_id
    nil
  end
end
