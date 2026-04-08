class EscrowTransactionSerializer < ApplicationSerializer
  attributes :id,
             :buyer_username,
             :buyer_avatar,
             :seller_username,
             :seller_avatar,
             :amount,
             :fee_amount,
             :total_with_fee,
             :currency,
             :payment_network,
             :status,
             :description,
             :payment_address,
             :created_at,
             :funded_at,
             :released_at,
             :disputed_at,
             :is_buyer,
             :is_seller

  def buyer_username
    object.buyer.username
  end

  def buyer_avatar
    object.buyer.avatar_template
  end

  def seller_username
    object.seller.username
  end

  def seller_avatar
    object.seller.avatar_template
  end

  def total_with_fee
    object.total_with_fee
  end

  def is_buyer
    scope&.current_user&.id == object.buyer_id
  end

  def is_seller
    scope&.current_user&.id == object.seller_id
  end
end
