# name: discourse-escrow
# about: Buyer/Seller escrow protection with NGN, USDT, USDC support
# version: 1.0.0
# authors: Techhive
# url: https://github.com/Techhive-Technologies/escrow/

enabled_site_setting :escrow_enabled

register_asset 'stylesheets/escrow.scss'

after_initialize do
  require_dependency 'application_controller'

  [
    '../app/models/escrow_transaction',
    '../app/controllers/krabit/escrow_controller',
    '../app/serializers/escrow_transaction_serializer'
  ].each { |path| load File.expand_path(path + '.rb', __FILE__) }

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
end
