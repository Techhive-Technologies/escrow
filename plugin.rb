# frozen_string_literal: true

# name: krabit-escrow
# about: Simple escrow system for KRABIT
# version: 1.0.0
# authors: KRABIT

enabled_site_setting :krabit_escrow_enabled

after_initialize do
  require_relative "app/models/krabit_escrow"
  require_relative "app/serializers/krabit_escrow_serializer"
  require_relative "app/controllers/krabit/escrows_controller"

  Discourse::Application.routes.append do
    namespace :krabit do
      resources :escrows, only: %i[index show create] do
        member do
          post :accept
          post :decline
          post :mark_delivered
          post :confirm
          post :dispute
          post :cancel
        end
      end
    end
  end
end
