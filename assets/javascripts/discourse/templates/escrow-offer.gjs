import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { on } from "@ember/modifier";

class EscrowOffer extends Component {
  @tracked escrow    = this.args.model;
  @tracked submitted = false;
  @tracked done      = false;
  @tracked outcome   = null;   // "accepted" | "declined"
  @tracked declineReason = "";
  @tracked showDeclineForm = false;

  get isSeller() {
    return this.escrow?.is_seller;
  }

  get isActionable() {
    return this.escrow?.status === "pending_acceptance";
  }

  get sellerGets() {
    const amount  = parseFloat(this.escrow?.amount  || 0);
    const fee     = parseFloat(this.escrow?.fee_amount || 0);
    return (amount - fee).toFixed(2);
  }

  get feePercent() {
    const amount = parseFloat(this.escrow?.amount || 0);
    const fee    = parseFloat(this.escrow?.fee_amount || 0);
    if (!amount) return "0";
    return ((fee / amount) * 100).toFixed(1);
  }

  // ── ACCEPT ─────────────────────────────────────────────────────────────────
  @action async accept() {
    if (!confirm("Accept this escrow deal? The buyer will be notified to make payment.")) return;
    this.submitted = true;
    try {
      await ajax(`/escrow/${this.escrow.id}/accept`, { type: "POST" });
      this.outcome = "accepted";
      this.done    = true;
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.submitted = false;
    }
  }

  // ── DECLINE ────────────────────────────────────────────────────────────────
  @action showDecline() {
    this.showDeclineForm = true;
  }

  @action async decline() {
    this.submitted = true;
    try {
      await ajax(`/escrow/${this.escrow.id}/decline`, {
        type: "POST",
        data: { reason: this.declineReason },
      });
      this.outcome = "declined";
      this.done    = true;
    } catch (err) {
      popupAjaxError(err);
    } finally {
      this.submitted = false;
    }
  }

  @action setReason(e) {
    this.declineReason = e.target.value;
  }

  <template>
    <div class="eo-page">

      {{! ── NOT THE SELLER ── }}
      {{#if (and (not this.isSeller) (not this.escrow.is_buyer))}}
        <div class="eo-blocked">
          <div class="eo-blocked__icon">🔒</div>
          <h2>Access Restricted</h2>
          <p>This offer page is only accessible to the parties involved in this deal.</p>
        </div>

      {{! ── BUYER VIEW (read-only) ── }}
      {{else if this.escrow.is_buyer}}
        <div class="eo-page__inner">
          <div class="eo-hero eo-hero--info">
            <span class="eo-hero__icon">⏳</span>
            <h2>Awaiting Seller Response</h2>
            <p>You created this escrow deal. The seller has been notified and will accept or decline shortly.</p>
            <a href="/my-escrows" class="btn btn-primary">View My Escrows</a>
          </div>
          <div class="eo-detail-card">
            {{! deal details below }}
            <div class="eo-deal-info">
              <h3 class="eo-deal-info__title">{{this.escrow.title}}</h3>
              {{#if this.escrow.description}}
                <p class="eo-deal-info__desc">{{this.escrow.description}}</p>
              {{/if}}
              <div class="eo-amounts">
                <div class="eo-amount">
                  <span class="eo-amount__label">Deal Amount</span>
                  <span class="eo-amount__value">{{this.escrow.amount}} {{this.escrow.currency}}</span>
                </div>
                <div class="eo-amount">
                  <span class="eo-amount__label">Platform Fee</span>
                  <span class="eo-amount__value">{{this.escrow.fee_amount}} {{this.escrow.currency}}</span>
                </div>
                <div class="eo-amount eo-amount--highlight">
                  <span class="eo-amount__label">Seller Receives</span>
                  <span class="eo-amount__value">{{this.sellerGets}} {{this.escrow.currency}}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

      {{! ── OUTCOME (after accept/decline) ── }}
      {{else if this.done}}
        {{#if (eq this.outcome "accepted")}}
          <div class="eo-page__inner">
            <div class="eo-hero eo-hero--success">
              <span class="eo-hero__icon">✅</span>
              <h2>Deal Accepted!</h2>
              <p>The buyer has been notified and will now make payment. Once funds are locked in escrow, you'll receive a notification to deliver.</p>
              <a href="/my-escrows" class="btn btn-primary">Go to My Escrows</a>
            </div>
          </div>
        {{else}}
          <div class="eo-page__inner">
            <div class="eo-hero eo-hero--declined">
              <span class="eo-hero__icon">❌</span>
              <h2>Deal Declined</h2>
              <p>The buyer has been notified that you declined this deal.</p>
              <a href="/my-escrows" class="btn btn-default">Go to My Escrows</a>
            </div>
          </div>
        {{/if}}

      {{! ── ALREADY ACTIONED ── }}
      {{else if (not this.isActionable)}}
        <div class="eo-page__inner">
          <div class="eo-hero eo-hero--info">
            <span class="eo-hero__icon">🛡️</span>
            <h2>Escrow #{{this.escrow.id}}</h2>
            <p>This deal is currently: <strong>{{this.escrow.status}}</strong></p>
            <a href="/my-escrows" class="btn btn-primary">View in My Escrows</a>
          </div>
        </div>

      {{! ── MAIN SELLER OFFER PAGE ── }}
      {{else}}
        <div class="eo-page__inner">

          {{! Header }}
          <div class="eo-header">
            <span class="eo-header__badge">New Escrow Offer</span>
            <h1 class="eo-header__title">{{this.escrow.title}}</h1>
            <p class="eo-header__sub">
              <strong>@{{this.escrow.buyer_username}}</strong> wants to open a secure escrow deal with you.
            </p>
          </div>

          {{! Deal card }}
          <div class="eo-detail-card">

            {{#if this.escrow.description}}
              <div class="eo-deal-desc">
                <span class="eo-deal-desc__label">Deal Description</span>
                <p>{{this.escrow.description}}</p>
              </div>
            {{/if}}

            <div class="eo-amounts">
              <div class="eo-amount">
                <span class="eo-amount__label">Deal Amount</span>
                <span class="eo-amount__value">{{this.escrow.amount}} {{this.escrow.currency}}</span>
              </div>
              <div class="eo-amount">
                <span class="eo-amount__label">Platform Fee ({{this.feePercent}}%)</span>
                <span class="eo-amount__value">{{this.escrow.fee_amount}} {{this.escrow.currency}}</span>
              </div>
              <div class="eo-amount eo-amount--highlight">
                <span class="eo-amount__label">You Receive</span>
                <span class="eo-amount__value eo-amount__value--big">{{this.sellerGets}} {{this.escrow.currency}}</span>
              </div>
            </div>

            <div class="eo-parties">
              <div class="eo-party">
                <span class="eo-party__role">Buyer</span>
                <span class="eo-party__name">@{{this.escrow.buyer_username}}</span>
              </div>
              <div class="eo-party__arrow">→</div>
              <div class="eo-party eo-party--you">
                <span class="eo-party__role">You (Seller)</span>
                <span class="eo-party__name">@{{this.escrow.seller_username}}</span>
              </div>
            </div>

            <div class="eo-how-it-works">
              <h4>How this works if you accept:</h4>
              <ol>
                <li>💳 Buyer makes payment — funds are locked securely</li>
                <li>🔒 You can see the funds are held before you deliver</li>
                <li>📦 You deliver and mark as done</li>
                <li>✅ Buyer confirms receipt — you get paid instantly</li>
                <li>⚠️ Either party can raise a dispute if needed</li>
              </ol>
            </div>
          </div>

          {{! Action area }}
          {{#if this.showDeclineForm}}
            <div class="eo-decline-form">
              <label class="eo-decline-form__label">Reason for declining (optional)</label>
              <textarea
                class="ke-input"
                rows="3"
                placeholder="Let the buyer know why you can't accept this deal..."
                {{on "input" this.setReason}}
              >{{this.declineReason}}</textarea>
              <div class="eo-actions">
                <button
                  class="btn btn-danger eo-btn-action"
                  {{on "click" this.decline}}
                  disabled={{this.submitted}}
                >
                  {{if this.submitted "Declining..." "Confirm Decline"}}
                </button>
                <button class="btn btn-default" {{on "click" (fn (mut this.showDeclineForm) false)}}>
                  Back
                </button>
              </div>
            </div>
          {{else}}
            <div class="eo-actions">
              <button
                class="btn btn-primary eo-btn-action eo-btn-action--accept"
                {{on "click" this.accept}}
                disabled={{this.submitted}}
              >
                {{if this.submitted "Accepting..." "✅ Accept Deal"}}
              </button>
              <button
                class="btn btn-default eo-btn-action eo-btn-action--decline"
                {{on "click" this.showDecline}}
              >
                ✕ Decline
              </button>
            </div>
            <p class="eo-accept-note">
              By accepting, you agree to deliver what was described before requesting payment release.
            </p>
          {{/if}}

        </div>
      {{/if}}

    </div>
  </template>
}

export default EscrowOffer;
