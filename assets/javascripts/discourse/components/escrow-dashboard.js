import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class EscrowDashboard extends Component {
  @tracked transactions    = [];
  @tracked isLoading       = true;
  @tracked showNewForm     = false;
  @tracked paymentInfo     = null;
  @tracked showBankForm    = false;
  @tracked pendingTx       = null;   // tx waiting for bank details

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
    this.showNewForm  = !this.showNewForm;
    this.paymentInfo  = null;
  }

  // ── BUYER: create deal ──────────────────────────────────────────────────────
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
      this.transactions  = [result, ...this.transactions];
      this.showNewForm   = false;
      this.sellerUsername = this.amount = this.description = "";
      alert("📨 Deal sent to seller! Waiting for them to accept.");
    } catch (e) { popupAjaxError(e); }
  }

  // ── SELLER: accept ──────────────────────────────────────────────────────────
  @action async acceptDeal(transaction) {
    try {
      await ajax(`/escrow/${transaction.id}/accept`, { type: "POST" });
      await this.loadTransactions();
      alert("✅ Deal accepted! The buyer will now make payment.");
    } catch (e) { popupAjaxError(e); }
  }

  // ── SELLER: decline ─────────────────────────────────────────────────────────
  @action async declineDeal(transaction) {
    const reason = prompt("Reason for declining (optional):");
    try {
      await ajax(`/escrow/${transaction.id}/decline`, {
        type: "POST",
        data: { reason },
      });
      await this.loadTransactions();
    } catch (e) { popupAjaxError(e); }
  }

  // ── BUYER: cancel ───────────────────────────────────────────────────────────
  @action async cancelDeal(transaction) {
    if (!confirm("Cancel this escrow deal?")) return;
    try {
      await ajax(`/escrow/${transaction.id}/cancel`, { type: "POST" });
      await this.loadTransactions();
    } catch (e) { popupAjaxError(e); }
  }

  // ── BUYER: pay ──────────────────────────────────────────────────────────────
  @action async fundEscrow(transaction) {
    try {
      const result = await ajax(`/escrow/${transaction.id}/fund`, { type: "POST" });
      if (result.type === "redirect") {
        window.location.href = result.payment_url;   // Paystack for NGN
      } else {
        this.paymentInfo = result;                    // show crypto address
      }
    } catch (e) { popupAjaxError(e); }
  }

  // ── SELLER: mark delivered ──────────────────────────────────────────────────
  @action async deliverEscrow(transaction) {
    if (!confirm("Mark this deal as delivered? The buyer will be notified to confirm.")) return;
    try {
      await ajax(`/escrow/${transaction.id}/deliver`, { type: "POST" });
      await this.loadTransactions();
      alert("📦 Marked as delivered! Waiting for buyer to confirm.");
    } catch (e) { popupAjaxError(e); }
  }

  // ── BUYER: confirm delivery ─────────────────────────────────────────────────
  @action async confirmDelivery(transaction) {
    if (transaction.currency === "NGN") {
      this.pendingTx   = transaction;
      this.showBankForm = true;
      return;
    }
    if (!confirm("Confirm delivery and release funds to seller? This cannot be undone.")) return;
    try {
      await ajax(`/escrow/${transaction.id}/complete`, { type: "POST" });
      await this.loadTransactions();
      alert("✅ Funds released! Seller will receive payment shortly.");
    } catch (e) { popupAjaxError(e); }
  }

  // ── NGN bank details submit ─────────────────────────────────────────────────
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

  // ── DISPUTE ─────────────────────────────────────────────────────────────────
  @action async disputeEscrow(transaction) {
    const reason = prompt("Describe the issue clearly. An admin will review:");
    if (!reason) return;
    try {
      await ajax(`/escrow/${transaction.id}/dispute`, {
        type: "POST",
        data: { reason },
      });
      await this.loadTransactions();
      alert("⚠️ Dispute raised. An admin will contact both parties.");
    } catch (e) { popupAjaxError(e); }
  }

  @action copyAddress(address) {
    navigator.clipboard.writeText(address);
    alert("✅ Address copied!");
  }
}
