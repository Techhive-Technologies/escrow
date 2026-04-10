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
  @tracked model       = [];
  @tracked showForm    = false;
  @tracked submitting  = false;

  // Form fields
  @tracked title          = "";
  @tracked sellerUsername = "";
  @tracked amount         = "";
  @tracked currency       = "NGN";
  @tracked description    = "";

  currencies = ["NGN", "USDT", "USDC"];

  constructor() {
    super(...arguments);
    this.loadEscrows();
  }

  async loadEscrows() {
    try {
      const data = await ajax("/escrow/");
      // Attach permission flags to each transaction
      this.model = (data.transactions || []).map((e) => this.withFlags(e));
    } catch (err) {
      popupAjaxError(err);
    }
  }

  // Computes which buttons to show per card
  withFlags(e) {
    return {
      ...e,
      can_accept:  e.is_seller && e.status === "pending_acceptance",
      can_decline: e.is_seller && e.status === "pending_acceptance",
      can_pay:     e.is_buyer  && e.status === "accepted",
      can_deliver: e.is_seller && e.status === "funded",
      can_confirm: e.is_buyer  && e.status === "delivered",
      can_dispute: (e.is_buyer || e.is_seller) && ["funded", "delivered"].includes(e.status),
      can_cancel:  e.is_buyer  && ["pending_acceptance", "accepted"].includes(e.status),
      // Convenience display fields
      seller_gets: (parseFloat(e.amount) - parseFloat(e.fee_amount || 0)).toFixed(2),
      fee_percent: e.fee_amount
        ? ((parseFloat(e.fee_amount) / parseFloat(e.amount)) * 100).toFixed(1)
        : "0",
    };
  }

  @action toggleForm() {
    this.showForm = !this.showForm;
  }

  @action setCurrency(e) {
    this.currency = e.target.value;
  }

  // ── CREATE ──────────────────────────────────────────────────────────────────
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
      this.model       = [this.withFlags(result), ...this.model];
      this.showForm    = false;
      this.title       = "";
      this.sellerUsername = "";
      this.amount      = "";
      this.description = "";
      alert("📨 Escrow sent to seller! Waiting for them to accept.");
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.submitting = false;
    }
  }

  // ── ACCEPT (Seller) ─────────────────────────────────────────────────────────
  @action async accept(escrow) {
    try {
      await ajax(`/escrow/${escrow.id}/accept`, { type: "POST" });
      await this.loadEscrows();
      alert("✅ Deal accepted! Buyer will now make payment.");
    } catch (err) { popupAjaxError(err); }
  }

  // ── DECLINE (Seller) ────────────────────────────────────────────────────────
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

  // ── PAY (Buyer) ─────────────────────────────────────────────────────────────
  @action async pay(escrow) {
    try {
      const result = await ajax(`/escrow/${escrow.id}/fund`, { type: "POST" });
      if (result.type === "redirect") {
        // NGN → Paystack redirect
        window.location.href = result.payment_url;
      } else {
        // Crypto → show address in prompt for now
        alert(
          `📤 Send exactly ${result.pay_amount} ${result.pay_currency} to:\n\n${result.payment_address}\n\nYour escrow will activate automatically once confirmed on-chain (1–15 min).`
        );
      }
    } catch (err) { popupAjaxError(err); }
  }

  // ── DELIVER (Seller) ────────────────────────────────────────────────────────
  @action async deliver(escrow) {
    if (!confirm("Mark this deal as delivered? The buyer will be notified.")) return;
    try {
      await ajax(`/escrow/${escrow.id}/deliver`, { type: "POST" });
      await this.loadEscrows();
      alert("📦 Marked as delivered! Waiting for buyer confirmation.");
    } catch (err) { popupAjaxError(err); }
  }

  // ── CONFIRM RECEIPT (Buyer) ─────────────────────────────────────────────────
  @action async confirm(escrow) {
    if (escrow.currency === "NGN") {
      const accountNumber = prompt("Seller's Account Number:");
      if (!accountNumber) return;
      const bankCode    = prompt("Seller's Bank Code (e.g. 044 for Access Bank):");
      if (!bankCode) return;
      const accountName = prompt("Seller's Account Name:");
      if (!accountName) return;
      if (!confirm("Release funds to seller? This cannot be undone.")) return;
      try {
        await ajax(`/escrow/${escrow.id}/complete`, {
          type: "POST",
          data: { account_number: accountNumber, bank_code: bankCode, account_name: accountName },
        });
        await this.loadEscrows();
        alert("✅ Funds released! Seller will receive NGN shortly.");
      } catch (err) { popupAjaxError(err); }
    } else {
      if (!confirm("Confirm delivery and release crypto funds? This cannot be undone.")) return;
      try {
        await ajax(`/escrow/${escrow.id}/complete`, { type: "POST" });
        await this.loadEscrows();
        alert("✅ Funds released to seller!");
      } catch (err) { popupAjaxError(err); }
    }
  }

  // ── DISPUTE ─────────────────────────────────────────────────────────────────
  @action async dispute(escrow) {
    const reason = prompt("Describe the issue clearly. An admin will review:");
    if (!reason) return;
    try {
      await ajax(`/escrow/${escrow.id}/dispute`, {
        type: "POST",
        data: { reason },
      });
      await this.loadEscrows();
      alert("⚠️ Dispute raised. An admin will contact both parties.");
    } catch (err) { popupAjaxError(err); }
  }

  // ── CANCEL (Buyer) ──────────────────────────────────────────────────────────
  @action async cancel(escrow) {
    if (!confirm("Cancel this escrow deal?")) return;
    try {
      await ajax(`/escrow/${escrow.id}/cancel`, { type: "POST" });
      await this.loadEscrows();
    } catch (err) { popupAjaxError(err); }
  }

  <template>
    <div class="krabit-page">
      <div class="krabit-header">
        <h2>🛡️ My Escrows</h2>
        <button class="btn btn-primary" {{on "click" this.toggleForm}}>
          {{if this.showForm "Cancel" "+ New Escrow"}}
        </button>
      </div>

      {{! ── CREATE FORM ── }}
      {{#if this.showForm}}
        <div class="krabit-form">
          <div class="krabit-form__row">
            <div class="krabit-form__field">
              <label>Title *</label>
              <Input @value={{this.title}} placeholder="What is this escrow for?" />
            </div>
            <div class="krabit-form__field">
              <label>Seller Username *</label>
              <Input @value={{this.sellerUsername}} placeholder="e.g. john_doe" />
            </div>
          </div>
          <div class="krabit-form__row">
            <div class="krabit-form__field">
              <label>Amount *</label>
              <Input @type="number" @value={{this.amount}} placeholder="0.00" />
            </div>
            <div class="krabit-form__field">
              <label>Currency</label>
              <select {{on "change" this.setCurrency}}>
                {{#each this.currencies as |c|}}
                  <option value={{c}} selected={{eq c this.currency}}>{{c}}</option>
                {{/each}}
              </select>
            </div>
          </div>
          <div class="krabit-form__field krabit-form__field--full">
            <label>Description</label>
            <Textarea @value={{this.description}} placeholder="What is being exchanged?" rows="3" />
          </div>
          <button
            class="btn btn-primary"
            {{on "click" this.create}}
            disabled={{this.submitting}}
          >
            {{if this.submitting "Creating..." "Create Escrow"}}
          </button>
        </div>
      {{/if}}

      {{! ── ESCROW CARDS ── }}
      {{#if this.model.length}}
        <div class="krabit-list">
          {{#each this.model as |e|}}
            <div class="krabit-card krabit-card--{{e.status}}">
              <div class="krabit-card__top">
                <span class="krabit-card__title">{{e.title}}</span>
                <span class="krabit-card__status">{{e.status}}</span>
              </div>
              <div class="krabit-card__meta">
                <span>💰 {{e.amount}} {{e.currency}}</span>
                <span>🛒 @{{e.buyer_username}} → 🏭 @{{e.seller_username}}</span>
                <span>Fee: {{e.fee_percent}}% · Seller gets: {{e.seller_gets}} {{e.currency}}</span>
              </div>
              {{#if e.description}}
                <p class="krabit-card__desc">{{e.description}}</p>
              {{/if}}
              {{#if e.dispute_reason}}
                <div class="krabit-card__dispute">⚠️ {{e.dispute_reason}}</div>
              {{/if}}
              
              {{#if e.pm_url}}
                <a class="btn btn-small" href={{e.pm_url}}>💬 View Thread</a>
              {{/if}}
              <div class="krabit-card__actions">
                {{#if e.can_accept}}
                  <button class="btn btn-primary btn-small" {{on "click" (fn this.accept e)}}>✅ Accept</button>
                {{/if}}
                {{#if e.can_decline}}
                  <button class="btn btn-danger btn-small" {{on "click" (fn this.decline e)}}>✕ Decline</button>
                {{/if}}
                {{#if e.can_pay}}
                  <button class="btn btn-primary btn-small" {{on "click" (fn this.pay e)}}>💳 Pay Now</button>
                {{/if}}
                {{#if e.can_deliver}}
                  <button class="btn btn-primary btn-small" {{on "click" (fn this.deliver e)}}>📦 Mark Delivered</button>
                {{/if}}
                {{#if e.can_confirm}}
                  <button class="btn btn-primary btn-small" {{on "click" (fn this.confirm e)}}>✅ Confirm Receipt</button>
                {{/if}}
                {{#if e.can_dispute}}
                  <button class="btn btn-danger btn-small" {{on "click" (fn this.dispute e)}}>⚠️ Dispute</button>
                {{/if}}
                {{#if e.can_cancel}}
                  <button class="btn btn-small" {{on "click" (fn this.cancel e)}}>Cancel</button>
                {{/if}}
              </div>
            </div>
          {{/each}}
        </div>
      {{else}}
        <div class="krabit-empty">
          <p>No escrows yet. Create one to get started.</p>
        </div>
      {{/if}}
    </div>
  </template>
}

export default MyEscrows;
