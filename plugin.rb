# name: KRABIT Escrow
# about: Buyer/Seller escrow protection with NGN, USDT, USDC support
# version: 1.0.0
# authors: Techhive
# url: https://github.com/Techhive-Technologies/escrow/

  Discourse::Application.routes.append do
    scope '/escrow' do
      get  '/'                    => 'escrow/escrow#index'
      post '/create'              => 'escrow/escrow#create'
      post '/:id/accept'          => 'escrow/escrow#accept'
      post '/:id/decline'         => 'escrow/escrow#decline'
      post '/:id/fund'            => 'escrow/escrow#fund'
      post '/:id/deliver'         => 'escrow/escrow#deliver'
      post '/:id/complete'        => 'escrow/escrow#complete'
      post '/:id/dispute'         => 'escrow/escrow#dispute'
      post '/:id/cancel'          => 'escrow/escrow#cancel'
      get  '/:id'                 => 'escrow/escrow#show'
      post '/webhook/paystack'    => 'escrow/escrow#paystack_webhook'
      post '/webhook/nowpayments' => 'escrow/escrow#nowpayments_webhook'
    end
  end
