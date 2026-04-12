class EscrowTransactionSerializer < ApplicationSerializer
  attributes :id,
             :title,
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
             :dispute_reason,
             :payment_address,
             :pm_url,
             :created_at,
             :funded_at,
             :completed_at,    # ← was released_at (wrong column name)
             :disputed_at,
             :is_buyer,
             :is_seller

  def title;          object.title.to_s;               end
  def buyer_username; object.buyer.username;            end
  def buyer_avatar;   object.buyer.avatar_template;     end
  def seller_username; object.seller.username;          end
  def seller_avatar;  object.seller.avatar_template;    end
  def total_with_fee; object.total_with_fee;            end
  def is_buyer;       scope&.current_user&.id == object.buyer_id;  end
  def is_seller;      scope&.current_user&.id == object.seller_id; end

  def pm_url
    topic = Topic.where(
      archetype: Archetype.private_message,
      user_id:   object.buyer_id
    ).where("title LIKE ?", "Escrow ##{object.id}%").first
    topic ? "/t/#{topic.slug}/#{topic.id}" : nil
  end
end
