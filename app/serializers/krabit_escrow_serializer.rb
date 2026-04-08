# frozen_string_literal: true

class KrabitEscrowSerializer < ApplicationSerializer
  attributes :id, :title, :description, :amount, :currency,
             :fee_percent, :fee_amount, :seller_gets,
             :status, :dispute_reason, :created_at,
             :can_accept, :can_decline, :can_deliver,
             :can_confirm, :can_dispute, :can_cancel,
             :buyer, :seller

  def buyer
    BasicUserSerializer.new(object.buyer, root: false)
  end

  def seller
    BasicUserSerializer.new(object.seller, root: false)
  end

  def can_accept  = object.status == "pending"    && scope&.id == object.seller_id
  def can_decline = object.status == "pending"    && scope&.id == object.seller_id
  def can_deliver = object.status == "funded"     && scope&.id == object.seller_id
  def can_confirm = object.status == "delivering" && scope&.id == object.buyer_id
  def can_dispute = object.status == "delivering" && scope&.id == object.buyer_id
  def can_cancel  = object.status == "pending"    && [object.buyer_id, object.seller_id].include?(scope&.id)
end
