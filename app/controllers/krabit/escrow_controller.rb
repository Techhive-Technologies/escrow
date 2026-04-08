require 'net/http'
require 'uri'
require 'json'
require 'openssl'

module DiscourseEscrow
  class EscrowController < ::ApplicationController
    requires_login except: [:paystack_webhook, :nowpayments_webhook]
    skip_before_action :verify_authenticity_token, only: [:paystack_webhook, :nowpayments_webhook]

    # GET /escrow — list your transactions
    def index
      transactions = EscrowTransaction
        .where('buyer_id = ? OR seller_id = ?', current_user.id, current_user.id)
        .order(created_at: :desc)

      render json: {
        transactions: ActiveModel::ArraySerializer.new(
          transactions,
          each_serializer: EscrowTransactionSerializer,
          scope: guardian
        )
      }
    end

    # GET /escrow/:id — view one transaction
    def show
      transaction = EscrowTransaction.find(params[:id])
      unless [transaction.buyer_id, transaction.seller_id].include?(current_user.id) || guardian.is_admin?
        return render json: { error: 'Not authorized' }, status: 403
      end
      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false)
    end

    # POST /escrow/create — buyer creates a deal
    def create
      seller = User.find_by(username: params[:seller_username])
      return render json: { error: 'Seller not found' }, status: 404       unless seller
      return render json: { error: 'You cannot escrow with yourself' }, status: 400 if seller.id == current_user.id

      currency = params[:currency].to_s.upcase
      return render json: { error: 'Unsupported currency' }, status: 400 unless EscrowTransaction::CURRENCIES.include?(currency)

      amount = params[:amount].to_f
      min = currency == 'NGN' ? SiteSetting.escrow_min_amount_ngn : SiteSetting.escrow_min_amount_usd
      return render json: { error: "Minimum amount is #{min} #{currency}" }, status: 400 if amount < min

      fee = (amount * SiteSetting.escrow_fee_percent / 100.0).round(2)

      transaction = EscrowTransaction.create!(
        buyer_id:    current_user.id,
        seller_id:   seller.id,
        amount:      amount,
        fee_amount:  fee,
        currency:    currency,
        description: params[:description],
        payment_network: params[:network]  # e.g. TRC20 for USDT
      )

      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false), status: 201
    end

    # POST /escrow/:id/fund — generate payment link or crypto address
    def fund
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Not authorized' }, status: 403 unless transaction.buyer_id == current_user.id
      return render json: { error: "Status must be 'pending_payment'" }, status: 400 unless transaction.pending?

      if transaction.ngn?
        result = paystack_initialize(transaction)
        return render json: { error: result['message'] }, status: 400 unless result['status']

        render json: {
          type:          'redirect',
          payment_url:   result['data']['authorization_url'],
          reference:     result['data']['reference']
        }

      else
        # USDT or USDC via NOWPayments
        network  = transaction.payment_network || 'TRC20'
        pay_curr = EscrowTransaction::CRYPTO_NETWORKS.dig(transaction.currency, network)
        return render json: { error: 'Unsupported network for this currency' }, status: 400 unless pay_curr

        result = nowpayments_create(transaction, pay_curr)
        return render json: { error: result['message'] }, status: 400 if result['code']

        transaction.update!(
          payment_reference: result['payment_id'].to_s,
          payment_address:   result['pay_address'],
          payment_network:   network
        )

        render json: {
          type:            'crypto',
          payment_address: result['pay_address'],
          pay_amount:      result['pay_amount'],
          pay_currency:    result['pay_currency'],
          payment_id:      result['payment_id'],
          network:         network
        }
      end
    end

    # POST /escrow/:id/release — buyer releases funds to seller
    def release
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Not authorized' }, status: 403 unless transaction.buyer_id == current_user.id
      return render json: { error: 'Can only release funded escrows' }, status: 400 unless transaction.funded?

      # For NGN: initiate Paystack transfer to seller
      if transaction.ngn?
        unless params[:account_number] && params[:bank_code]
          return render json: { error: 'Seller bank account details required for NGN release' }, status: 400
        end

        transaction.update!(
          seller_account_number: params[:account_number],
          seller_bank_code:      params[:bank_code],
          seller_account_name:   params[:account_name]
        )

        payout = paystack_transfer(transaction)
        unless payout['status']
          return render json: { error: "Payout failed: #{payout['message']}" }, status: 400
        end
      end
      # NOTE: For crypto, NOWPayments payout API or admin manual transfer
      # Future enhancement: automate crypto payouts

      transaction.release!
      render json: { success: true, message: 'Funds released successfully. Seller will receive payment shortly.' }
    end

    # POST /escrow/:id/dispute
    def dispute
      transaction = EscrowTransaction.find(params[:id])
      parties = [transaction.buyer_id, transaction.seller_id]
      return render json: { error: 'Not authorized' }, status: 403 unless parties.include?(current_user.id)
      return render json: { error: 'Can only dispute funded escrows' }, status: 400 unless transaction.funded?

      transaction.dispute!(current_user.id)
      render json: { success: true, message: 'Dispute raised. An admin will review and contact both parties.' }
    end

    # ─── WEBHOOKS ──────────────────────────────────────────────────────────────

    # Paystack calls this when buyer's NGN payment succeeds
    def paystack_webhook
      payload   = request.body.read
      signature = request.headers['X-Paystack-Signature']
      computed  = OpenSSL::HMAC.hexdigest('SHA512', SiteSetting.paystack_secret_key, payload)

      return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(computed, signature.to_s)

      event = JSON.parse(payload)

      if event['event'] == 'charge.success'
        ref = event['data']['reference']
        t   = EscrowTransaction.find_by(payment_reference: ref)
        t&.fund!
      end

      head :ok
    end

    # NOWPayments calls this when crypto payment is confirmed
    def nowpayments_webhook
      payload = request.body.read
      event   = JSON.parse(payload)

      # Verify IPN signature
      sig         = request.headers['x-nowpayments-sig']
      sorted_body = event.sort.to_h.to_json
      computed    = OpenSSL::HMAC.hexdigest('SHA512', SiteSetting.nowpayments_ipn_secret, sorted_body)

      return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(computed, sig.to_s)

      if %w[confirmed finished].include?(event['payment_status'])
        payment_id = event['payment_id'].to_s
        t = EscrowTransaction.find_by(payment_reference: payment_id)
        t&.fund!
      end

      head :ok
    end

    private

    # ─── PAYSTACK HELPERS ──────────────────────────────────────────────────────

    def paystack_initialize(transaction)
      uri  = URI('https://api.paystack.co/transaction/initialize')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = "Bearer #{SiteSetting.paystack_secret_key}"
      req['Content-Type']  = 'application/json'
      req.body = {
        email:     transaction.buyer.email,
        amount:    (transaction.total_with_fee * 100).to_i,  # kobo
        reference: "escrow_#{transaction.id}_#{SecureRandom.hex(6)}",
        metadata:  {
          escrow_id:    transaction.id,
          custom_fields: [
            { display_name: 'Escrow ID',  variable_name: 'escrow_id',  value: transaction.id },
            { display_name: 'Seller',     variable_name: 'seller',     value: transaction.seller.username }
          ]
        }
      }.to_json

      res = http.request(req)
      result = JSON.parse(res.body)
      transaction.update!(payment_reference: result.dig('data', 'reference')) if result['status']
      result
    end

    def paystack_transfer(transaction)
      # Step 1: Create transfer recipient
      recip_uri  = URI('https://api.paystack.co/transferrecipient')
      http       = Net::HTTP.new(recip_uri.host, recip_uri.port)
      http.use_ssl = true

      req = Net::HTTP::Post.new(recip_uri)
      req['Authorization'] = "Bearer #{SiteSetting.paystack_secret_key}"
      req['Content-Type']  = 'application/json'
      req.body = {
        type:           'nuban',
        name:           transaction.seller_account_name,
        account_number: transaction.seller_account_number,
        bank_code:      transaction.seller_bank_code,
        currency:       'NGN'
      }.to_json

      recip_res    = http.request(req)
      recip_result = JSON.parse(recip_res.body)
      return recip_result unless recip_result['status']

      recipient_code = recip_result['data']['recipient_code']

      # Step 2: Initiate transfer
      transfer_uri = URI('https://api.paystack.co/transfer')
      req2 = Net::HTTP::Post.new(transfer_uri)
      req2['Authorization'] = "Bearer #{SiteSetting.paystack_secret_key}"
      req2['Content-Type']  = 'application/json'
      req2.body = {
        source:    'balance',
        amount:    (transaction.amount * 100).to_i,  # seller gets amount minus fee
        recipient: recipient_code,
        reason:    "Escrow ##{transaction.id} release"
      }.to_json

      transfer_res = http.request(req2)
      JSON.parse(transfer_res.body)
    end

    # ─── NOWPAYMENTS HELPER ────────────────────────────────────────────────────

    def nowpayments_create(transaction, pay_currency)
      uri  = URI('https://api.nowpayments.io/v1/payment')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      req = Net::HTTP::Post.new(uri)
      req['x-api-key']    = SiteSetting.nowpayments_api_key
      req['Content-Type'] = 'application/json'
      req.body = {
        price_amount:      transaction.total_with_fee,
        price_currency:    'usd',
        pay_currency:      pay_currency,
        order_id:          transaction.id.to_s,
        order_description: "Escrow ##{transaction.id} — #{transaction.description}",
        ipn_callback_url:  "#{Discourse.base_url}/escrow/webhook/nowpayments"
      }.to_json

      res = http.request(req)
      JSON.parse(res.body)
    end
  end
end
