import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
import { eq } from "truth-helpers";
import { Input, Textarea } from "@ember/component";

class MyEscrows extends Component {
  @tracked model          = [];
  @tracked showForm       = false;
  @tracked submitting     = false;
  @tracked isLoading      = true;
  @tracked cryptoPayment  = null;   // holds crypto address info inline

  // Form fields
  @tracked title          = "";
  @tracked sellerUsername = "";
  @tracked amount         = "";
  @tracked currency       = "NGN";
  @tracked description    = "";

  // NGN bank details (shown inline when confirming)
  @tracked showBankForm   = false;
  @tracked pendingConfirm = null;
  @tracked bankAccount    = "";
  @tracked bankCode       = "";
  @tracked bankName       = "";

  currencies = ["NGN", "USDT", "USDC"];

  constructor() {
    super(...arguments);
    this.loadEscrows();
  }

  // ── DATA ────────────────────────────────────────────────────────────────────

  async loadEscrows() {
    this.isLoading = true;
    try {
      const data = await ajax("/escrow/");
      this.model = (data.transactions || []).map((e) => this.withFlags(e));
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.isLoading = false;
    }
  }

  withFlags(e) {
    const statusLabels = {
      pending_acceptance: "Awaiting Seller",
      accepted:           "Accepted — Pay Now",
      pending_payment:    "Payment Pending",
      funded:             "Funds Locked 🔒",
      delivered:          "Delivered — Awaiting Confirmation",
      completed:          "Completed ✅",
      disputed:           "Disputed ⚠️",
      resolved:           "Resolved",
      refunded:           "Refunded",
      declined:           "Declined",
      cancelled:          "Cancelled",
    };
    return {
      ...e,
      status_label: statusLabels[e.status] || e.status,
      can_accept:   e.is_seller && e.status === "pending_acceptance",
      can_decline:  e.is_seller && e.status === "pending_acceptance",
      can_pay:      e.is_buyer  && e.status === "accepted",
      can_deliver:  e.is_seller && e.status === "funded",
      can_confirm:  e.is_buyer  && e.status === "delivered",
      can_dispute:  (e.is_buyer || e.is_seller) && ["funded", "delivered"].includes(e.status),
      can_cancel:   e.is_buyer  && ["pending_acceptance", "accepted"].includes(e.status),
      seller_gets:  (parseFloat(e.amount) - parseFloat(e.fee_amount || 0)).toFixed(2),
      fee_percent:  e.fee_amount
        ? ((parseFloat(e.fee_amount) / parseFloat(e.amount)) * 100).toFixed(1)
        : "0",
      role: e.is_buyer ? "Buyer" : "Seller",
    };
  }

  // ── FORM ACTIONS ────────────────────────────────────────────────────────────

  @action toggleForm() {
    this.showForm = !this.showForm;
    this.cryptoPayment = null;
    this.showBankForm  = false;
  }

  @action setCurrency(ev) {
    this.currency = ev.target.value;
  }

  @action async create() {
    if (!this.title || !this.sellerUsername || !this.amount) {
      alert("Please fill in Title, Seller Username and Amount.");
      return;
    }
    this.submitting = true;
    try {
      const result = await ajax("/escrow/create", {
        type: "POST",
        data: {
          title:           this.title,
          seller_username: this.sellerUsername,
          amount:          this.amount,
          currency:        this.currency,
          description:     this.description,
        },
      });
      this.model          = [this.withFlags(result), ...this.model];
      this.showForm       = false;
      this.title          = "";
      this.sellerUsername = "";
      this.amount         = "";
      this.description    = "";
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.submitting = false;
    }
  }

  // ── ESCROW ACTIONS ──────────────────────────────────────────────────────────

  @action async accept(escrow) {
    if (!confirm("Accept this escrow deal?")) return;
    try {
      await ajax(`/escrow/${escrow.id}/accept`, { type: "POST" });
      await this.loadEscrows();
    } catch (err) { popupAjaxError(err); }
  }

  @action async decline(escrow) {
    const reason = prompt("Reason for declining (optional):");
    try {
      await ajax(`/escrow/${escrow.id}/decline`, {
        type: "POST",
        data: { reason: reason || "" },
      });
      await this.loadEscrows();
    } catch (err) { popupAjaxError(err); }
  }

  @action async pay(escrow) {
    try {
      const result = await ajax(`/escrow/${escrow.id}/fund`, { type: "POST" });
      if (result.type === "redirect") {
        window.location.href = result.payment_url;
      } else {
        // Show crypto address inline — no alert
        this.cryptoPayment = { ...result, escrow_id: escrow.id };
        await this.loadEscrows();
      }
    } catch (err) { popupAjaxError(err); }
  }

  @action copyAddress() {
    if (this.cryptoPayment?.payment_address) {
      navigator.clipboard.writeText(this.cryptoPayment.payment_address);
    }
  }

  @action dismissCrypto() {
    this.cryptoPayment = null;
  }

  @action async deliver(escrow) {
    if (!confirm("Mark this deal as delivered? The buyer will be notified to confirm.")) return;
    try {
      await ajax(`/escrow/${escrow.id}/deliver`, { type: "POST" });
      await this.loadEscrows();
    } catch (err) { popupAjaxError(err); }
  }

  @action confirmReceipt(escrow) {
    if (escrow.currency === "NGN") {
      this.pendingConfirm = escrow;
      this.showBankForm   = true;
    } else {
      this.doConfirm(escrow);
    }
  }

  @action async doConfirm(escrow) {
    if (!confirm("Release funds to seller? This cannot be undone.")) return;
    try {
      await ajax(`/escrow/${escrow.id}/complete`, { type: "POST" });
      await this.loadEscrows();
    } catch (err) { popupAjaxError(err); }
  }

  @action async submitBankDetails() {
    if (!this.bankAccount || !this.bankCode || !this.bankName) {
      alert("Please fill in all bank details.");
      return;
    }
    if (!confirm("Release funds to seller? This cannot be undone.")) return;
    try {
      await ajax(`/escrow/${this.pendingConfirm.id}/complete`, {
        type: "POST",
        data: { account_number: this.bankAccount, bank_code: this.bankCode, account_name: this.bankName },
      });
      this.showBankForm   = false;
      this.pendingConfirm = null;
      this.bankAccount    = "";
      this.bankCode       = "";
      this.bankName       = "";
      await this.loadEscrows();
    } catch (err) { popupAjaxError(err); }
  }

  @action cancelBankForm() {
    this.showBankForm   = false;
    this.pendingConfirm = null;
  }

  @action async dispute(escrow) {
    const reason = prompt("Describe the issue clearly. An admin will be notified:");
    if (!reason) return;
    try {
      await ajax(`/escrow/${escrow.id}/dispute`, { type: "POST", data: { reason } });
      await this.loadEscrows();
    } catch (err) { popupAjaxError(err); }
  }

  @action async cancel(escrow) {
    if (!confirm("Cancel this escrow deal?")) return;
    try {
      await ajax(`/escrow/${escrow.id}/cancel`, { type: "POST" });
      await this.loadEscrows();
    } catch (err) { popupAjaxError(err); }
  }

  <template>
    <div class="ke-page">

      {{! ── PAGE HEADER ── }}
      <div class="ke-page__header">
        <div class="ke-page__title">
          <span class="ke-shield">🛡️</span>
          <div>
            <h2>My Escrows</h2>
            <p>Secure buyer &amp; seller protection</p>
          </div>
        </div>
        <button class="btn {{if this.showForm 'btn-default' 'btn-primary'}} ke-btn-new"
          {{on "click" this.toggleForm}}>
          {{if this.showForm "✕ Cancel" "+ New Escrow"}}
        </button>
      </div>

      {{! ── CREATE FORM ── }}
      {{#if this.showForm}}
        <div class="ke-form">
          <h3 class="ke-form__title">New Escrow Deal</h3>
          <p class="ke-form__subtitle">The seller will be notified and must accept before you pay.</p>

          <div class="ke-form__grid">
            <div class="ke-form__field">
              <label class="ke-label">Deal Title <span class="ke-required">*</span></label>
              <Input @value={{this.title}} placeholder="e.g. iPhone 14 Pro purchase" class="ke-input" />
            </div>
            <div class="ke-form__field">
              <label class="ke-label">Seller Username <span class="ke-required">*</span></label>
              <Input @value={{this.sellerUsername}} placeholder="e.g. john_doe" class="ke-input" />
            </div>
            <div class="ke-form__field">
              <label class="ke-label">Amount <span class="ke-required">*</span></label>
              <Input @type="number" @value={{this.amount}} placeholder="0.00" class="ke-input" />
            </div>
            <div class="ke-form__field">
              <label class="ke-label">Currency</label>
              <select class="ke-input ke-select" {{on "change" this.setCurrency}}>
                {{#each this.currencies as |c|}}
                  <option value={{c}} selected={{eq c this.currency}}>{{c}}</option>
                {{/each}}
              </select>
            </div>
            <div class="ke-form__field ke-form__field--full">
              <label class="ke-label">Description</label>
              <Textarea
                @value={{this.description}}
                placeholder="Describe what is being bought, sold, or delivered..."
                rows="3"
                class="ke-input"
              />
            </div>
          </div>

          <div class="ke-form__footer">
            <button
              class="btn btn-primary ke-btn-submit"
              {{on "click" this.create}}
              disabled={{this.submitting}}
            >
              {{if this.submitting "Creating..." "📨 Send to Seller"}}
            </button>
          </div>
        </div>
      {{/if}}

      {{! ── BANK DETAILS FORM (NGN confirm) ── }}
      {{#if this.showBankForm}}
        <div class="ke-form ke-form--bank">
          <h3 class="ke-form__title">🏦 Seller's Bank Details</h3>
          <p class="ke-form__subtitle">Enter the seller's bank account to release the NGN payout.</p>
          <div class="ke-form__grid">
            <div class="ke-form__field">
              <label class="ke-label">Account Number</label>
              <Input @value={{this.bankAccount}} placeholder="e.g. 0123456789" class="ke-input" />
            </div>
            <div class="ke-form__field">
              <label class="ke-label">Bank Code</label>
              <Input @value={{this.bankCode}} placeholder="e.g. 044 = Access Bank" class="ke-input" />
            </div>
            <div class="ke-form__field ke-form__field--full">
              <label class="ke-label">Account Name</label>
              <Input @value={{this.bankName}} placeholder="As it appears on the bank account" class="ke-input" />
            </div>
          </div>
          <div class="ke-form__footer">
            <button class="btn btn-danger ke-btn-submit" {{on "click" this.submitBankDetails}}>
              ✅ Confirm &amp; Release Funds
            </button>
            <button class="btn btn-default" {{on "click" this.cancelBankForm}}>Cancel</button>
          </div>
        </div>
      {{/if}}

      {{! ── CRYPTO PAYMENT PANEL ── }}
      {{#if this.cryptoPayment}}
        <div class="ke-crypto-panel">
          <div class="ke-crypto-panel__header">
            <span class="ke-crypto-panel__icon">📤</span>
            <div>
              <strong>Send Crypto Payment</strong>
              <span>Send exactly the amount below to the address shown</span>
            </div>
            <button class="ke-crypto-panel__close" {{on "click" this.dismissCrypto}}>✕</button>
          </div>
          <div class="ke-crypto-panel__amount">
            {{this.cryptoPayment.pay_amount}}
            <span>{{this.cryptoPayment.pay_currency}}</span>
          </div>
          <div class="ke-crypto-panel__address">
            <code>{{this.cryptoPayment.payment_address}}</code>
            <button class="btn btn-small ke-btn-copy" {{on "click" this.copyAddress}}>
              📋 Copy
            </button>
          </div>
          <p class="ke-crypto-panel__note">
            ⚠️ Send the exact amount shown. Your escrow will activate automatically once the transaction is confirmed on-chain — this usually takes 1–15 minutes.
          </p>
        </div>
      {{/if}}

      {{! ── LOADING ── }}
      {{#if this.isLoading}}
        <div class="ke-loading">
          <div class="ke-loading__spinner"></div>
          <span>Loading your escrows...</span>
        </div>

      {{! ── EMPTY STATE ── }}
      {{else if (eq this.model.length 0)}}
        <div class="ke-empty">
          <div class="ke-empty__icon">🛡️</div>
          <h3>No escrow deals yet</h3>
          <p>Create your first escrow deal to start trading safely.<br>Funds are held securely until both parties are satisfied.</p>
          <button class="btn btn-primary" {{on "click" this.toggleForm}}>
            + Create Your First Escrow
          </button>
        </div>

      {{! ── DEAL CARDS ── }}
      {{else}}
        <div class="ke-list">
          {{#each this.model as |e|}}
            <div class="ke-card ke-card--{{e.status}}">

              {{! Card Header }}
              <div class="ke-card__header">
                <div class="ke-card__header-left">
                  <span class="ke-card__id">#{{e.id}}</span>
                  <span class="ke-badge ke-badge--{{e.status}}">{{e.status_label}}</span>
                </div>
                <div class="ke-card__header-right">
                  <span class="ke-card__role ke-role--{{e.role}}">{{e.role}}</span>
                  {{#if e.pm_url}}
                    <a class="ke-thread-link" href={{e.pm_url}}>💬 Thread</a>
                  {{/if}}
                </div>
              </div>

              {{! Deal Info }}
              <div class="ke-card__body">
                <h3 class="ke-card__title">{{e.title}}</h3>
                {{#if e.description}}
                  <p class="ke-card__desc">{{e.description}}</p>
                {{/if}}

                <div class="ke-card__parties">
                  <div class="ke-party">
                    <span class="ke-party__label">Buyer</span>
                    <span class="ke-party__name">@{{e.buyer_username}}</span>
                  </div>
                  <div class="ke-party__arrow">→</div>
                  <div class="ke-party">
                    <span class="ke-party__label">Seller</span>
                    <span class="ke-party__name">@{{e.seller_username}}</span>
                  </div>
                </div>

                <div class="ke-card__amounts">
                  <div class="ke-amount ke-amount--total">
                    <span class="ke-amount__label">Total</span>
                    <span class="ke-amount__value">{{e.amount}} {{e.currency}}</span>
                  </div>
                  <div class="ke-amount ke-amount--fee">
                    <span class="ke-amount__label">Fee ({{e.fee_percent}}%)</span>
                    <span class="ke-amount__value">{{e.fee_amount}} {{e.currency}}</span>
                  </div>
                  <div class="ke-amount ke-amount--seller">
                    <span class="ke-amount__label">Seller Receives</span>
                    <span class="ke-amount__value">{{e.seller_gets}} {{e.currency}}</span>
                  </div>
                </div>

                {{#if e.dispute_reason}}
                  <div class="ke-dispute-reason">
                    <strong>⚠️ Dispute reason:</strong> {{e.dispute_reason}}
                  </div>
                {{/if}}
              </div>

              {{! Action Buttons }}
              {{#if (or e.can_accept e.can_decline e.can_pay e.can_deliver e.can_confirm e.can_dispute e.can_cancel)}}
                <div class="ke-card__actions">
                  {{#if e.can_accept}}
                    <button class="btn btn-primary ke-action-btn"
                      {{on "click" (fn this.accept e)}}>
                      ✅ Accept Deal
                    </button>
                  {{/if}}
                  {{#if e.can_decline}}
                    <button class="btn btn-danger ke-action-btn ke-action-btn--outline"
                      {{on "click" (fn this.decline e)}}>
                      ✕ Decline
                    </button>
                  {{/if}}
                  {{#if e.can_pay}}
                    <button class="btn btn-primary ke-action-btn"
                      {{on "click" (fn this.pay e)}}>
                      💳 Make Payment
                    </button>
                  {{/if}}
                  {{#if e.can_deliver}}
                    <button class="btn btn-primary ke-action-btn"
                      {{on "click" (fn this.deliver e)}}>
                      📦 Mark as Delivered
                    </button>
                  {{/if}}
                  {{#if e.can_confirm}}
                    <button class="btn btn-primary ke-action-btn"
                      {{on "click" (fn this.confirmReceipt e)}}>
                      ✅ Confirm Receipt
                    </button>
                  {{/if}}
                  {{#if e.can_dispute}}
                    <button class="btn btn-danger ke-action-btn ke-action-btn--outline"
                      {{on "click" (fn this.dispute e)}}>
                      ⚠️ Dispute
                    </button>
                  {{/if}}
                  {{#if e.can_cancel}}
                    <button class="btn btn-default ke-action-btn ke-action-btn--ghost"
                      {{on "click" (fn this.cancel e)}}>
                      Cancel
                    </button>
                  {{/if}}
                </div>
              {{/if}}

            </div>
          {{/each}}
        </div>
      {{/if}}

    </div>
  </template>
}

export default MyEscrows;
