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
    '../app/controllers/discourse_escrow/escrow_controller',
    '../app/serializers/escrow_transaction_serializer'
  ].each { |path| load File.expand_path(path + '.rb', __FILE__) }

  Discourse::Application.routes.append do
    scope '/escrow' do
      get  '/'              => 'discourse_escrow/escrow#index'
      post '/create'        => 'discourse_escrow/escrow#create'
      post '/:id/fund'      => 'discourse_escrow/escrow#fund'
      post '/:id/release'   => 'discourse_escrow/escrow#release'
      post '/:id/dispute'   => 'discourse_escrow/escrow#dispute'
      get  '/:id'           => 'discourse_escrow/escrow#show'
      post '/webhook/paystack'     => 'discourse_escrow/escrow#paystack_webhook'
      post '/webhook/nowpayments'  => 'discourse_escrow/escrow#nowpayments_webhook'
    end
  end
end
