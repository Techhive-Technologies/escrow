# frozen_string_literal: true

# name: krabit-escrow
# about: Escrow system for KRABIT marketplace on Discourse
# version: 1.0.0
# authors: KRABIT
# url: https://krabit.com

enabled_site_setting :krabit_escrow_enabled

after_initialize do
  %w[
    ../app/models/krabit_escrow
    ../app/models/krabit_escrow_payment
    ../app/controllers/krabit/escrows_controller
    ../app/serializers/krabit_escrow_serializer
  ].each { |path| require File.expand_path(path, __FILE__) }

  Discourse::Application.routes.append do
    namespace :krabit do
      resources :escrows, only: [:index, :show, :create] do
        member do
          post :accept         # counterpart accepts the escrow request
          post :decline        # counterpart declines the escrow request
          post :mark_paid      # admin confirms payment received
          post :mark_delivering # seller marks as delivered
          post :confirm        # buyer confirms receipt
          post :dispute        # buyer raises dispute
          post :release        # admin force-releases to seller
          post :refund         # admin refunds buyer
        end
      end
    end
  end

  add_to_serializer(:user, :krabit_escrow_stats) do
    {
      total_as_buyer:  KrabitEscrow.where(buyer_id: object.id).count,
      total_as_seller: KrabitEscrow.where(seller_id: object.id).count,
      active:          KrabitEscrow
                         .where("buyer_id = ? OR seller_id = ?", object.id, object.id)
                         .where(status: %w[pending accepted paid delivering disputed])
                         .count,
    }
  end
end
