import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class MyEscrowsController extends Controller {
  @tracked showCreateForm = false;
  @tracked creating = false;

  // Form fields
  @tracked newMyRole = "buyer";
  @tracked newCounterpartUsername = "";
  @tracked newTitle = "";
  @tracked newDescription = "";
  @tracked newAmount = "";
  @tracked newCurrency = "USDT";

  currencies = ["USDT", "USDC", "USD_WIRE", "NGN_BANK"];
  currencyLabels = {
    USDT:     "USDT (Tether)",
    USDC:     "USDC (USD Coin)",
    USD_WIRE: "USD Wire Transfer",
    NGN_BANK: "NGN Bank Transfer",
  };

  @action toggleCreateForm() {
    this.showCreateForm = !this.showCreateForm;
  }

  @action
  async createEscrow() {
    if (!this.newTitle || !this.newCounterpartUsername || !this.newAmount) return;

    this.creating = true;
    try {
      const result = await ajax("/krabit/escrows.json", {
        type: "POST",
        data: {
          escrow: {
            my_role:               this.newMyRole,
            counterpart_username:  this.newCounterpartUsername,
            title:                 this.newTitle,
            description:           this.newDescription,
            amount:                this.newAmount,
            currency:              this.newCurrency,
          },
        },
      });
      this.model.unshiftObject(result);
      this.showCreateForm = false;
      this._resetForm();
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.creating = false;
    }
  }

  @action
  async acceptEscrow(escrow) {
    try {
      const result = await ajax(`/krabit/escrows/${escrow.id}/accept.json`, { type: "POST" });
      Object.assign(escrow, result);
    } catch (e) { popupAjaxError(e); }
  }

  @action
  async declineEscrow(escrow) {
    const reason = prompt("Reason for declining (optional):");
    try {
      const result = await ajax(`/krabit/escrows/${escrow.id}/decline.json`, {
        type: "POST",
        data: { reason },
      });
      Object.assign(escrow, result);
    } catch (e) { popupAjaxError(e); }
  }

  @action
  async markDelivering(escrow) {
    if (!confirm("Mark this escrow as delivered? The buyer will be notified to confirm receipt.")) return;
    try {
      const result = await ajax(`/krabit/escrows/${escrow.id}/mark_delivering.json`, { type: "POST" });
      Object.assign(escrow, result);
    } catch (e) { popupAjaxError(e); }
  }

  @action
  async confirmEscrow(escrow) {
    if (!confirm("Confirm you have received the delivery? This will release funds to the seller.")) return;
    try {
      const result = await ajax(`/krabit/escrows/${escrow.id}/confirm.json`, { type: "POST" });
      Object.assign(escrow, result);
    } catch (e) { popupAjaxError(e); }
  }

  @action
  async disputeEscrow(escrow) {
    const reason = prompt("Please describe the issue:");
    if (!reason) return;
    try {
      const result = await ajax(`/krabit/escrows/${escrow.id}/dispute.json`, {
        type: "POST",
        data: { reason },
      });
      Object.assign(escrow, result);
    } catch (e) { popupAjaxError(e); }
  }

  @action
  openPmThread(escrow) {
    if (escrow.pm_topic_id) {
      window.location.href = `/t/${escrow.pm_topic_id}`;
    }
  }

  _resetForm() {
    this.newMyRole = "buyer";
    this.newCounterpartUsername = "";
    this.newTitle = "";
    this.newDescription = "";
    this.newAmount = "";
    this.newCurrency = "USDT";
  }
}
