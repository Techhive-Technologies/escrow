# name: escrow
# about: Buyer/Seller escrow protection with NGN, USDT, USDC support
# version: 1.0.0
# authors: Techhive
# url: https://github.com/Techhive-Technologies/escrow/

enabled_site_setting :escrow_enabled

register_asset 'stylesheets/escrow.scss'

after_initialize do
  # These paths correctly point to your current file structure
  load File.expand_path('../app/models/escrow_transaction.rb', __FILE__)
  load File.expand_path('../app/controllers/krabit/escrow_controller.rb', __FILE__)
  load File.expand_path('../app/serializers/escrow_transaction_serializer.rb', __FILE__)

  Discourse::Application.routes.append do
    # Frontend page
    get '/my-escrows' => 'application#index', format: false
    get '/escrow-offer/:id' => 'application#index', format: false

    
    # API - This correctly points to Krabit::EscrowController
    scope '/escrow' do
      get  '/'                    => 'krabit/escrow#index'
      post '/create'              => 'krabit/escrow#create'
      post '/:id/accept'          => 'krabit/escrow#accept'
      post '/:id/decline'         => 'krabit/escrow#decline'
      post '/:id/fund'            => 'krabit/escrow#fund'
      post '/:id/deliver'         => 'krabit/escrow#deliver'
      post '/:id/complete'        => 'krabit/escrow#complete'
      post '/:id/dispute'         => 'krabit/escrow#dispute'
      post '/:id/cancel'          => 'krabit/escrow#cancel'
      get  '/:id'                 => 'krabit/escrow#show'
      post '/webhook/paystack'    => 'krabit/escrow#paystack_webhook'
      post '/webhook/nowpayments' => 'krabit/escrow#nowpayments_webhook'
    end
  end
end
