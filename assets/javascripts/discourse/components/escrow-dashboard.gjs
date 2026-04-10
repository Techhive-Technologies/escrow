import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq, and, not } from "truth-helpers";
import { Input, Textarea } from "@ember/component";

export default class EscrowDashboard extends Component {
  @tracked transactions   = [];
  @tracked isLoading      = true;
  @tracked showNewForm    = false;
  @tracked paymentInfo    = null;
  @tracked showBankForm   = false;
  @tracked pendingTx      = null;

  // New deal form
  @tracked sellerUsername = "";
  @tracked amount         = "";
  @tracked currency       = "NGN";
  @tracked network        = "TRC20";
  @tracked description    = "";

  // Bank details form
  @tracked accountNumber  = "";
  @tracked bankCode       = "";
  @tracked accountName    = "";

  constructor() {
    super(...arguments);
    this.loadTransactions();
  }

  get cryptoCurrencySelected() {
    return this.currency === "USDT" || this.currency === "USDC";
  }

  get networkOptions() {
    if (this.currency === "USDT") {
      return [
        { id: "TRC20", name: "TRC-20 (Tron) — Cheapest" },
        { id: "ERC20", name: "ERC-20 (Ethereum)" },
        { id: "BEP20", name: "BEP-20 (BSC)" },
      ];
    }
    if (this.currency === "USDC") {
      return [
        { id: "ERC20", name: "ERC-20 (Ethereum)" },
        { id: "BEP20", name: "BEP-20 (BSC)" },
      ];
    }
    return [];
  }

  async loadTransactions() {
    try {
      const data = await ajax("/escrow/");
      this.transactions = data.transactions;
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.isLoading = false;
    }
  }

  @action toggleNewForm() {
    this.showNewForm = !this.showNewForm;
    this.paymentInfo = null;
  }

  @action setCurrency(e) { this.currency = e.target.value; }
  @action setNetwork(e)  { this.network  = e.target.value; }

  @action async createEscrow() {
    try {
      const result = await ajax("/escrow/create", {
        type: "POST",
        data: {
          seller_username: this.sellerUsername,
          amount:          this.amount,
          currency:        this.currency,
          network:         this.network,
          description:     this.description,
        },
      });
      this.transactions   = [result, ...this.transactions];
      this.showNewForm    = false;
      this.sellerUsername = this.amount = this.description = "";
      alert("📨 Deal sent to seller! Waiting for them to accept.");
    } catch (e) { popupAjaxError(e); }
  }

  @action async acceptDeal(tx) {
    try {
      await ajax(`/escrow/${tx.id}/accept`, { type: "POST" });
      await this.loadTransactions();
      alert("✅ Deal accepted! Buyer will now make payment.");
    } catch (e) { popupAjaxError(e); }
  }

  @action async declineDeal(tx) {
    const reason = prompt("Reason for declining (optional):");
    try {
      await ajax(`/escrow/${tx.id}/decline`, { type: "POST", data: { reason } });
      await this.loadTransactions();
    } catch (e) { popupAjaxError(e); }
  }

  @action async cancelDeal(tx) {
    if (!confirm("Cancel this escrow deal?")) return;
    try {
      await ajax(`/escrow/${tx.id}/cancel`, { type: "POST" });
      await this.loadTransactions();
    } catch (e) { popupAjaxError(e); }
  }

  @action async fundEscrow(tx) {
    try {
      const result = await ajax(`/escrow/${tx.id}/fund`, { type: "POST" });
      if (result.type === "redirect") {
        window.location.href = result.payment_url;
      } else {
        this.paymentInfo = result;
      }
    } catch (e) { popupAjaxError(e); }
  }

  @action async deliverEscrow(tx) {
    if (!confirm("Mark as delivered? Buyer will be notified to confirm.")) return;
    try {
      await ajax(`/escrow/${tx.id}/deliver`, { type: "POST" });
      await this.loadTransactions();
      alert("📦 Marked as delivered! Waiting for buyer confirmation.");
    } catch (e) { popupAjaxError(e); }
  }

  @action async confirmDelivery(tx) {
    if (tx.currency === "NGN") {
      this.pendingTx    = tx;
      this.showBankForm = true;
      return;
    }
    if (!confirm("Confirm delivery and release funds? This cannot be undone.")) return;
    try {
      await ajax(`/escrow/${tx.id}/complete`, { type: "POST" });
      await this.loadTransactions();
      alert("✅ Funds released to seller!");
    } catch (e) { popupAjaxError(e); }
  }

  @action async submitBankDetails() {
    if (!this.accountNumber || !this.bankCode || !this.accountName) {
      alert("Please fill in all bank details.");
      return;
    }
    if (!confirm("Release funds to seller? This cannot be undone.")) return;
    try {
      await ajax(`/escrow/${this.pendingTx.id}/complete`, {
        type: "POST",
        data: {
          account_number: this.accountNumber,
          bank_code:      this.bankCode,
          account_name:   this.accountName,
        },
      });
      this.showBankForm = false;
      this.pendingTx    = null;
      await this.loadTransactions();
      alert("✅ Funds released! Seller will receive NGN shortly.");
    } catch (e) { popupAjaxError(e); }
  }

  @action cancelBankForm() {
    this.showBankForm = false;
    this.pendingTx    = null;
  }

  @action async disputeEscrow(tx) {
    const reason = prompt("Describe the issue. An admin will review:");
    if (!reason) return;
    try {
      await ajax(`/escrow/${tx.id}/dispute`, { type: "POST", data: { reason } });
      await this.loadTransactions();
      alert("⚠️ Dispute raised. An admin will contact both parties.");
    } catch (e) { popupAjaxError(e); }
  }

  @action copyAddress(address) {
    navigator.clipboard.writeText(address);
    alert("✅ Address copied!");
  }

  <template>
    <div class="escrow-dashboard">
      <div class="escrow-header">
        <h1>🛡️ Escrow</h1>
        <button class="btn btn-primary" {{on "click" this.toggleNewForm}}>
          {{if this.showNewForm "✕ Cancel" "+ New Deal"}}
        </button>
      </div>

      {{! ── NEW DEAL FORM ── }}
      {{#if this.showNewForm}}
        <div class="escrow-form card">
          <h3>Create Escrow Deal</h3>
          <p class="escrow-hint">Seller will be notified to accept before you pay.</p>

          <label>Seller Username</label>
          <Input @value={{this.sellerUsername}} placeholder="e.g. johndoe" class="escrow-input" />

          <label>Amount</label>
          <Input @value={{this.amount}} type="number" placeholder="e.g. 50000" class="escrow-input" />

          <label>Currency</label>
          <select class="escrow-input" {{on "change" this.setCurrency}}>
            <option value="NGN">🇳🇬 NGN — Naira</option>
            <option value="USDT">💵 USDT — Tether</option>
            <option value="USDC">💵 USDC — USD Coin</option>
          </select>

          {{#if this.cryptoCurrencySelected}}
            <label>Network</label>
            <select class="escrow-input" {{on "change" this.setNetwork}}>
              {{#each this.networkOptions as |opt|}}
                <option value={{opt.id}}>{{opt.name}}</option>
              {{/each}}
            </select>
          {{/if}}

          <label>Deal Description</label>
          <Textarea @value={{this.description}} placeholder="What is being sold or delivered?" class="escrow-input" />

          <button class="btn btn-primary" {{on "click" this.createEscrow}}>
            📨 Send to Seller
          </button>
        </div>
      {{/if}}

      {{! ── CRYPTO PAYMENT INFO ── }}
      {{#if this.paymentInfo}}
        <div class="escrow-payment-info card">
          <h3>📤 Send Crypto Payment</h3>
          <p>Send exactly <strong>{{this.paymentInfo.pay_amount}} {{this.paymentInfo.pay_currency}}</strong> to:</p>
          <div class="escrow-address">
            <code>{{this.paymentInfo.payment_address}}</code>
            <button class="btn btn-small" {{on "click" (fn this.copyAddress this.paymentInfo.payment_address)}}>
              📋 Copy
            </button>
          </div>
          <p class="escrow-note">⚠️ Send the exact amount. Escrow activates automatically once confirmed on-chain (1–15 min).</p>
        </div>
      {{/if}}

      {{! ── NGN BANK DETAILS FORM ── }}
      {{#if this.showBankForm}}
        <div class="escrow-form card">
          <h3>🏦 Enter Seller's Bank Details for Payout</h3>
          <Input @value={{this.accountNumber}} placeholder="Account Number" class="escrow-input" />
          <Input @value={{this.bankCode}}      placeholder="Bank Code (e.g. 044 = Access Bank)" class="escrow-input" />
          <Input @value={{this.accountName}}   placeholder="Account Name" class="escrow-input" />
          <button class="btn btn-success" {{on "click" this.submitBankDetails}}>✅ Confirm & Release</button>
          <button class="btn" {{on "click" this.cancelBankForm}}>Cancel</button>
        </div>
      {{/if}}

      {{! ── TRANSACTION LIST ── }}
      {{#if this.isLoading}}
        <p class="escrow-loading">Loading transactions...</p>
      {{else if this.transactions.length}}
        {{#each this.transactions as |tx|}}
          <div class="escrow-card card status-{{tx.status}}">

            <div class="escrow-card-header">
              <span class="escrow-id">#{{tx.id}}</span>
              <span class="escrow-badge badge-{{tx.status}}">{{tx.status}}</span>
              <span class="escrow-amount">{{tx.amount}} {{tx.currency}}</span>
            </div>

            <p class="escrow-description">{{tx.description}}</p>

            <div class="escrow-parties">
              <span>🧑 Buyer: <strong>{{tx.buyer_username}}</strong></span>
              <span>🧑 Seller: <strong>{{tx.seller_username}}</strong></span>
            </div>

            {{#if tx.fee_amount}}
              <p class="escrow-fee">Fee: {{tx.fee_amount}} {{tx.currency}}</p>
            {{/if}}

            <div class="escrow-actions">

              {{! SELLER: accept or decline }}
              {{#if (and tx.is_seller (eq tx.status "pending_acceptance"))}}
                <button class="btn btn-success" {{on "click" (fn this.acceptDeal tx)}}>✅ Accept Deal</button>
                <button class="btn btn-danger"  {{on "click" (fn this.declineDeal tx)}}>❌ Decline</button>
              {{/if}}

              {{! BUYER: pay }}
              {{#if (and tx.is_buyer (eq tx.status "accepted"))}}
                <button class="btn btn-primary" {{on "click" (fn this.fundEscrow tx)}}>💳 Make Payment</button>
                <button class="btn"             {{on "click" (fn this.cancelDeal tx)}}>🚫 Cancel</button>
              {{/if}}

              {{! SELLER: mark delivered }}
              {{#if (and tx.is_seller (eq tx.status "funded"))}}
                <button class="btn btn-primary" {{on "click" (fn this.deliverEscrow tx)}}>📦 Mark as Delivered</button>
              {{/if}}

              {{! BUYER: confirm or dispute }}
              {{#if (and tx.is_buyer (eq tx.status "delivered"))}}
                <button class="btn btn-success" {{on "click" (fn this.confirmDelivery tx)}}>✅ Confirm & Release Funds</button>
                <button class="btn btn-danger"  {{on "click" (fn this.disputeEscrow tx)}}>⚠️ Dispute</button>
              {{/if}}

              {{! SELLER: dispute if buyer unresponsive after delivery }}
              {{#if (and tx.is_seller (eq tx.status "delivered"))}}
                <button class="btn btn-danger" {{on "click" (fn this.disputeEscrow tx)}}>⚠️ Raise Dispute</button>
              {{/if}}

            </div>
          </div>
        {{/each}}
      {{else}}
        <p class="escrow-empty">🛡️ No escrow deals yet. Click "+ New Deal" to get started.</p>
      {{/if}}

    </div>
  </template>
}
