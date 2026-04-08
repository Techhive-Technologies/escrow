import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class EscrowDashboard extends Component {
  @tracked transactions = [];
  @tracked isLoading = true;
  @tracked showNewForm = false;
  @tracked selectedTransaction = null;
  @tracked paymentInfo = null;

  // Form fields
  @tracked sellerUsername = "";
  @tracked amount = "";
  @tracked currency = "NGN";
  @tracked network = "TRC20";
  @tracked description = "";

  // Release form fields
  @tracked accountNumber = "";
  @tracked bankCode = "";
  @tracked accountName = "";

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
        { id: "TRC20", name: "TRC-20 (Tron) — Cheapest fees" },
        { id: "ERC20", name: "ERC-20 (Ethereum)" },
        { id: "BEP20", name: "BEP-20 (BSC)" },
      ];
    } else if (this.currency === "USDC") {
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

  @action
  toggleNewForm() {
    this.showNewForm = !this.showNewForm;
    this.paymentInfo = null;
  }

  @action
  async createEscrow() {
    try {
      const result = await ajax("/escrow/create", {
        type: "POST",
        data: {
          seller_username: this.sellerUsername,
          amount: this.amount,
          currency: this.currency,
          network: this.network,
          description: this.description,
        },
      });
      this.transactions = [result, ...this.transactions];
      this.showNewForm = false;
      this.selectedTransaction = result;
      // Reset form
      this.sellerUsername = "";
      this.amount = "";
      this.description = "";
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async fundEscrow(transaction) {
    try {
      const result = await ajax(`/escrow/${transaction.id}/fund`, {
        type: "POST",
      });

      if (result.type === "redirect") {
        // NGN — redirect to Paystack
        window.location.href = result.payment_url;
      } else {
        // Crypto — show address
        this.paymentInfo = result;
        this.selectedTransaction = transaction;
      }
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async releaseEscrow(transaction) {
    if (transaction.currency === "NGN") {
      // Show bank details form first
      this.selectedTransaction = transaction;
      this.showReleaseForm = true;
      return;
    }

    if (!confirm("Release funds to seller? This cannot be undone.")) return;

    try {
      await ajax(`/escrow/${transaction.id}/release`, { type: "POST" });
      await this.loadTransactions();
      alert("✅ Funds released! Seller will receive payment shortly.");
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async releaseWithBankDetails(transaction) {
    if (!this.accountNumber || !this.bankCode || !this.accountName) {
      alert("Please fill in all bank details.");
      return;
    }

    if (!confirm("Release funds to seller? This cannot be undone.")) return;

    try {
      await ajax(`/escrow/${transaction.id}/release`, {
        type: "POST",
        data: {
          account_number: this.accountNumber,
          bank_code: this.bankCode,
          account_name: this.accountName,
        },
      });
      this.showReleaseForm = false;
      await this.loadTransactions();
      alert("✅ Funds released! Seller will receive NGN shortly.");
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async disputeEscrow(transaction) {
    const reason = prompt("Briefly describe the issue (this will be sent to admins):");
    if (!reason) return;

    try {
      await ajax(`/escrow/${transaction.id}/dispute`, { type: "POST" });
      await this.loadTransactions();
      alert("⚠️ Dispute raised. An admin will review and contact both parties.");
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  copyAddress(address) {
    navigator.clipboard.writeText(address);
    alert("✅ Address copied to clipboard!");
  }
}
