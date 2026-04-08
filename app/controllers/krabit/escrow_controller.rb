require 'net/http'
require 'uri'
require 'json'
require 'openssl'

module Krabit
  class EscrowController < ::ApplicationController
    requires_login except: [:paystack_webhook, :nowpayments_webhook]
    skip_before_action :verify_authenticity_token, only: [:paystack_webhook, :nowpayments_webhook]

    # GET /escrow
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

    # GET /escrow/:id
    def show
      transaction = EscrowTransaction.find(params[:id])
      unless [transaction.buyer_id, transaction.seller_id].include?(current_user.id) || guardian.is_admin?
        return render json: { error: 'Not authorized' }, status: 403
      end
      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false)
    end

    # POST /escrow/create  — Buyer creates the deal (no payment yet)
    def create
      seller = User.find_by(username: params[:seller_username])
      return render json: { error: 'Seller not found' }, status: 404        unless seller
      return render json: { error: 'Cannot escrow with yourself' }, status: 400 if seller.id == current_user.id

      currency = params[:currency].to_s.upcase
      return render json: { error: 'Unsupported currency' }, status: 400 unless EscrowTransaction::CURRENCIES.include?(currency)

      amount = params[:amount].to_f
      min = currency == 'NGN' ? SiteSetting.escrow_min_amount_ngn : SiteSetting.escrow_min_amount_usd
      return render json: { error: "Minimum is #{min} #{currency}" }, status: 400 if amount < min

      fee = (amount * SiteSetting.escrow_fee_percent / 100.0).round(2)

      transaction = EscrowTransaction.create!(
        buyer_id:        current_user.id,
        seller_id:       seller.id,
        amount:          amount,
        fee_amount:      fee,
        currency:        currency,
        payment_network: params[:network],
        description:     params[:description],
        status:          'pending_acceptance'   # ← starts here now
      )

      # Notify seller immediately
      seller.notifications.create!(
        notification_type: Notification.types[:custom],
        data: {
          message: "🛡️ #{current_user.username} wants to open an escrow deal with you for #{amount} #{currency}. Review and accept or decline.",
          url: "/escrow/#{transaction.id}"
        }.to_json
      )

      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false), status: 201
    end

    # POST /escrow/:id/accept  — Seller accepts
    def accept
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the seller can accept' }, status: 403 unless transaction.seller_id == current_user.id
      return render json: { error: 'Deal is not pending acceptance' }, status: 400 unless transaction.accept!
      render json: { success: true, message: 'Deal accepted! Buyer will now make payment.' }
    end

    # POST /escrow/:id/decline  — Seller declines
    def decline
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the seller can decline' }, status: 403 unless transaction.seller_id == current_user.id
      reason = params[:reason]
      return render json: { error: 'Deal cannot be declined at this stage' }, status: 400 unless transaction.decline!(reason)
      render json: { success: true, message: 'Deal declined.' }
    end

    # POST /escrow/:id/fund  — Buyer initiates payment (after seller accepted)
    def fund
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the buyer can pay' }, status: 403 unless transaction.buyer_id == current_user.id
      return render json: { error: 'Seller must accept the deal first' }, status: 400 unless transaction.status == 'accepted'

      # Move to pending_payment before generating payment link
      transaction.update!(status: 'pending_payment')

      if transaction.ngn?
        result = paystack_initialize(transaction)
        return render json: { error: result['message'] }, status: 400 unless result['status']
        render json: { type: 'redirect', payment_url: result['data']['authorization_url'] }
      else
        network  = transaction.payment_network || 'TRC20'
        pay_curr = EscrowTransaction::CRYPTO_NETWORKS.dig(transaction.currency, network)
        return render json: { error: 'Unsupported network' }, status: 400 unless pay_curr

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

    # POST /escrow/:id/deliver  — Seller marks as delivered
    def deliver
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the seller can mark as delivered' }, status: 403 unless transaction.seller_id == current_user.id
      return render json: { error: 'Funds must be in escrow first' }, status: 400 unless transaction.deliver!
      render json: { success: true, message: 'Marked as delivered. Waiting for buyer confirmation.' }
    end

    # POST /escrow/:id/complete  — Buyer confirms delivery, releases funds
    def complete
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the buyer can confirm' }, status: 403 unless transaction.buyer_id == current_user.id
      return render json: { error: 'Seller must mark as delivered first' }, status: 400 unless transaction.status == 'delivered'

      # NGN payout to seller
      if transaction.ngn?
        unless params[:account_number] && params[:bank_code] && params[:account_name]
          return render json: { error: 'Seller bank details required for NGN payout' }, status: 400
        end
        transaction.update!(
          seller_account_number: params[:account_number],
          seller_bank_code:      params[:bank_code],
          seller_account_name:   params[:account_name]
        )
        payout = paystack_transfer(transaction)
        return render json: { error: "Payout failed: #{payout['message']}" }, status: 400 unless payout['status']
      end

      transaction.complete!
      render json: { success: true, message: '✅ Confirmed! Seller will receive payment shortly.' }
    end

    # POST /escrow/:id/dispute  — Buyer disputes after delivery (or seller disputes)
    def dispute
      transaction = EscrowTransaction.find(params[:id])
      parties = [transaction.buyer_id, transaction.seller_id]
      return render json: { error: 'Not authorized' }, status: 403 unless parties.include?(current_user.id)
      return render json: { error: 'Can only dispute funded or delivered escrows' }, status: 400 unless transaction.dispute!(current_user.id, params[:reason])
      render json: { success: true, message: '⚠️ Dispute raised. An admin will review shortly.' }
    end

    # POST /escrow/:id/cancel  — Buyer cancels before payment
    def cancel
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the buyer can cancel' }, status: 403 unless transaction.buyer_id == current_user.id
      return render json: { error: 'Cannot cancel at this stage' }, status: 400 unless transaction.cancel!
      render json: { success: true, message: 'Escrow cancelled.' }
    end

    # ── WEBHOOKS ────────────────────────────────────────────────────────────────

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

    def nowpayments_webhook
      payload = request.body.read
      event   = JSON.parse(payload)
      sig     = request.headers['x-nowpayments-sig']
      computed = OpenSSL::HMAC.hexdigest('SHA512', SiteSetting.nowpayments_ipn_secret, event.sort.to_h.to_json)
      return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(computed, sig.to_s)

      if %w[confirmed finished].include?(event['payment_status'])
        t = EscrowTransaction.find_by(payment_reference: event['payment_id'].to_s)
        t&.fund!
      end
      head :ok
    end

    private

    def paystack_initialize(transaction)
      uri  = URI('https://api.paystack.co/transaction/initialize')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = "Bearer #{SiteSetting.paystack_secret_key}"
      req['Content-Type']  = 'application/json'
      req.body = {
        email:     transaction.buyer.email,
        amount:    (transaction.total_with_fee * 100).to_i,
        reference: "escrow_#{transaction.id}_#{SecureRandom.hex(6)}",
        metadata:  { escrow_id: transaction.id }
      }.to_json
      res    = http.request(req)
      result = JSON.parse(res.body)
      transaction.update!(payment_reference: result.dig('data', 'reference')) if result['status']
      result
    end

    def paystack_transfer(transaction)
      http = Net::HTTP.new('api.paystack.co', 443)
      http.use_ssl = true

      # Create recipient
      req = Net::HTTP::Post.new('/transferrecipient')
      req['Authorization'] = "Bearer #{SiteSetting.paystack_secret_key}"
      req['Content-Type']  = 'application/json'
      req.body = {
        type:           'nuban',
        name:           transaction.seller_account_name,
        account_number: transaction.seller_account_number,
        bank_code:      transaction.seller_bank_code,
        currency:       'NGN'
      }.to_json
      r = JSON.parse(http.request(req).body)
      return r unless r['status']

      # Initiate transfer
      req2 = Net::HTTP::Post.new('/transfer')
      req2['Authorization'] = "Bearer #{SiteSetting.paystack_secret_key}"
      req2['Content-Type']  = 'application/json'
      req2.body = {
        source:    'balance',
        amount:    (transaction.amount * 100).to_i,
        recipient: r['data']['recipient_code'],
        reason:    "Escrow ##{transaction.id} payout"
      }.to_json
      JSON.parse(http.request(req2).body)
    end

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
        order_description: "Escrow ##{transaction.id}",
        ipn_callback_url:  "#{Discourse.base_url}/escrow/webhook/nowpayments"
      }.to_json
      JSON.parse(http.request(req).body)
    end
  end
end
