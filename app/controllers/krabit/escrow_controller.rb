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

    # POST /escrow/create — Buyer creates the deal (no payment yet)
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
        title:           params[:title],
        status:          'pending_acceptance'
      )

      # Notify seller via forum notification
      seller.notifications.create!(
        notification_type: Notification.types[:custom],
        data: {
          message: "🛡️ #{current_user.username} wants to open an escrow deal with you for #{amount} #{currency}. Review and accept or decline.",
          url: "/my-escrows"
        }.to_json
      )

      # Open a private message thread between buyer and seller
      create_escrow_thread(transaction, seller)

      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false), status: 201
    end

    # POST /escrow/:id/accept — Seller accepts
    def accept
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the seller can accept' }, status: 403 unless transaction.seller_id == current_user.id
      return render json: { error: 'Deal is not pending acceptance' }, status: 400 unless transaction.accept!

      # Notify buyer
      transaction.buyer.notifications.create!(
        notification_type: Notification.types[:custom],
        data: {
          message: "✅ #{current_user.username} accepted your escrow deal ##{transaction.id}. You can now make payment.",
          url: "/my-escrows"
        }.to_json
      )

      # Post a status update into the deal thread
      post_to_escrow_thread(transaction, "✅ **#{current_user.username}** has **accepted** this deal. The buyer can now proceed with payment.")

      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false)
    end

    # POST /escrow/:id/decline — Seller declines
    def decline
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the seller can decline' }, status: 403 unless transaction.seller_id == current_user.id
      reason = params[:reason].to_s
      return render json: { error: 'Deal cannot be declined at this stage' }, status: 400 unless transaction.decline!(reason)

      # Notify buyer
      transaction.buyer.notifications.create!(
        notification_type: Notification.types[:custom],
        data: {
          message: "❌ #{current_user.username} declined escrow deal ##{transaction.id}. Reason: #{reason}",
          url: "/my-escrows"
        }.to_json
      )

      # Post a status update into the deal thread
      post_to_escrow_thread(transaction, "❌ **#{current_user.username}** has **declined** this deal.#{reason.present? ? " Reason: #{reason}" : ''}")

      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false)
    end

    # POST /escrow/:id/fund — Buyer initiates payment (after seller accepted)
    def fund
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the buyer can pay' }, status: 403 unless transaction.buyer_id == current_user.id
      return render json: { error: 'Seller must accept the deal first' }, status: 400 unless transaction.status == 'accepted'

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

    # POST /escrow/:id/deliver — Seller marks as delivered
    def deliver
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the seller can mark as delivered' }, status: 403 unless transaction.seller_id == current_user.id
      return render json: { error: 'Funds must be in escrow first' }, status: 400 unless transaction.deliver!

      # Notify buyer
      transaction.buyer.notifications.create!(
        notification_type: Notification.types[:custom],
        data: {
          message: "📦 #{current_user.username} marked escrow ##{transaction.id} as delivered. Please confirm or dispute.",
          url: "/my-escrows"
        }.to_json
      )

      # Post a status update into the deal thread
      post_to_escrow_thread(transaction, "📦 **#{current_user.username}** has marked this deal as **delivered**.\n\n@#{transaction.buyer.username} — please go to [My Escrows](/my-escrows) to **Confirm Receipt** or raise a **Dispute**.")

      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false)
    end

    # POST /escrow/:id/complete — Buyer confirms delivery, releases funds
    def complete
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the buyer can confirm' }, status: 403 unless transaction.buyer_id == current_user.id
      return render json: { error: 'Seller must mark as delivered first' }, status: 400 unless transaction.status == 'delivered'

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

      # Notify seller
      transaction.seller.notifications.create!(
        notification_type: Notification.types[:custom],
        data: {
          message: "✅ #{transaction.buyer.username} confirmed receipt on escrow ##{transaction.id}. #{transaction.amount} #{transaction.currency} is being sent to you.",
          url: "/my-escrows"
        }.to_json
      )

      # Post a status update into the deal thread
      post_to_escrow_thread(transaction, "✅ **#{transaction.buyer.username}** has confirmed receipt and **released the funds**.\n\n💰 **#{transaction.amount} #{transaction.currency}** is being sent to @#{transaction.seller.username}.\n\nThis deal is now complete. Thank you! 🎉")

      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false)
    end

    # POST /escrow/:id/dispute
    def dispute
      transaction = EscrowTransaction.find(params[:id])
      parties = [transaction.buyer_id, transaction.seller_id]
      return render json: { error: 'Not authorized' }, status: 403 unless parties.include?(current_user.id)
      return render json: { error: 'Can only dispute funded or delivered escrows' }, status: 400 unless transaction.dispute!(current_user.id, params[:reason])

      # Notify admins
      User.where(admin: true).each do |admin|
        admin.notifications.create!(
          notification_type: Notification.types[:custom],
          data: {
            message: "⚠️ Dispute raised on Escrow ##{transaction.id} by #{current_user.username}. Reason: #{params[:reason]}",
            url: "/my-escrows"
          }.to_json
        )
      end

      # Post a status update into the deal thread (admins are added here)
      post_to_escrow_thread(
        transaction,
        "⚠️ **Dispute raised** by @#{current_user.username}.\n\n**Reason:** #{params[:reason]}\n\nAn admin has been notified and will review this deal. Please do not delete any messages in this thread.",
        add_admins: true
      )

      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false)
    end

    # POST /escrow/:id/cancel — Buyer cancels before payment
    def cancel
      transaction = EscrowTransaction.find(params[:id])
      return render json: { error: 'Only the buyer can cancel' }, status: 403 unless transaction.buyer_id == current_user.id
      return render json: { error: 'Cannot cancel at this stage' }, status: 400 unless transaction.cancel!

      # Post a status update into the deal thread
      post_to_escrow_thread(transaction, "🚫 **#{current_user.username}** has **cancelled** this deal.")

      render json: EscrowTransactionSerializer.new(transaction, scope: guardian, root: false)
    end

    # ── WEBHOOKS ──────────────────────────────────────────────────────────────

    def paystack_webhook
      payload   = request.body.read
      signature = request.headers['X-Paystack-Signature']
      computed  = OpenSSL::HMAC.hexdigest('SHA512', SiteSetting.paystack_secret_key, payload)
      return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(computed, signature.to_s)

      event = JSON.parse(payload)
      if event['event'] == 'charge.success'
        ref = event['data']['reference']
        t   = EscrowTransaction.find_by(payment_reference: ref)
        if t&.fund!
          post_to_escrow_thread(t, "💰 **Payment confirmed!** #{t.amount} #{t.currency} is now **locked in escrow**.\n\n@#{t.seller.username} — please deliver and click **Mark Delivered** when done.")
        end
      end
      head :ok
    end

    def nowpayments_webhook
      payload  = request.body.read
      event    = JSON.parse(payload)
      sig      = request.headers['x-nowpayments-sig']
      computed = OpenSSL::HMAC.hexdigest('SHA512', SiteSetting.nowpayments_ipn_secret, event.sort.to_h.to_json)
      return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(computed, sig.to_s)

      if %w[confirmed finished].include?(event['payment_status'])
        t = EscrowTransaction.find_by(payment_reference: event['payment_id'].to_s)
        if t&.fund!
          post_to_escrow_thread(t, "💰 **Crypto payment confirmed!** #{t.amount} #{t.currency} is now **locked in escrow**.\n\n@#{t.seller.username} — please deliver and click **Mark Delivered** when done.")
        end
      end
      head :ok
    end

    private

    # ── PRIVATE MESSAGE HELPERS ───────────────────────────────────────────────

    # Creates the initial PM thread when a deal is opened
    def create_escrow_thread(transaction, seller)
      title       = transaction.title.to_s.truncate(60)
      description = transaction.description.to_s

      message_body = <<~MD
        ## 🛡️ Escrow Deal ##{transaction.id} — #{title}

        | | |
        |---|---|
        | **Buyer** | @#{transaction.buyer.username} |
        | **Seller** | @#{seller.username} |
        | **Amount** | #{transaction.amount} #{transaction.currency} |
        | **Platform Fee** | #{transaction.fee_amount} #{transaction.currency} |
        | **Seller Receives** | #{(transaction.amount - transaction.fee_amount).round(2)} #{transaction.currency} |

        **Description:** #{description.present? ? description : '_No description provided_'}

        ---

        Use this thread for **all communications** about this deal.

        ### How this works:
        1. 🟡 **Seller** — accept or decline this deal on [My Escrows](/my-escrows)
        2. 💳 **Buyer** — make payment once seller accepts
        3. 🔒 Funds are locked in escrow until delivery is confirmed
        4. 📦 **Seller** — mark as delivered when done
        5. ✅ **Buyer** — confirm receipt to release funds, or raise a dispute

        > ⚠️ Funds will **not** be released until the buyer clicks **Confirm Receipt** on the [My Escrows](/my-escrows) page.

        Good luck with your deal! 🤝
      MD

      post = PostCreator.create!(
        transaction.buyer,
        title:            "🛡️ Escrow ##{transaction.id} — #{title}",
        raw:              message_body,
        archetype:        Archetype.private_message,
        target_usernames: seller.username,
        skip_validations: true
      )

      # Store the topic ID on the transaction so we can post to it later
      transaction.update!(pm_topic_id: post.topic_id) if transaction.respond_to?(:pm_topic_id=)

    rescue => e
      Rails.logger.error("Escrow PM creation failed for ##{transaction.id}: #{e.message}")
    end

    # Posts a status update into the existing deal thread
    def post_to_escrow_thread(transaction, message, add_admins: false)
      # Find the topic — first try stored ID, then search by title
      topic = if transaction.respond_to?(:pm_topic_id) && transaction.pm_topic_id.present?
        Topic.find_by(id: transaction.pm_topic_id)
      else
        Topic.where(archetype: Archetype.private_message)
             .where("title LIKE ?", "🛡️ Escrow ##{transaction.id}%")
             .first
      end

      return unless topic

      # Add admins to the thread if this is a dispute
      if add_admins
        User.where(admin: true).each do |admin|
          topic.topic_allowed_users.find_or_create_by!(user_id: admin.id)
        end
      end

      # Post the system message as the buyer (deal creator)
      PostCreator.create!(
        transaction.buyer,
        topic_id:         topic.id,
        raw:              message,
        skip_validations: true
      )

    rescue => e
      Rails.logger.error("Escrow thread post failed for ##{transaction.id}: #{e.message}")
    end

    # ── PAYMENT HELPERS ───────────────────────────────────────────────────────

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
