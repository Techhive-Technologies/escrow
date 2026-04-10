import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class MyEscrowsController extends Controller {
  @tracked showForm = false;
  @tracked submitting = false;
  @tracked title = "";
  @tracked description = "";
  @tracked sellerUsername = "";
  @tracked amount = "";
  @tracked currency = "NGN";
  currencies = ["NGN", "USDT", "USDC"];

  @action toggleForm() { this.showForm = !this.showForm; }

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
          description:     this.description,
          seller_username: this.sellerUsername,
          amount:          this.amount,
          currency:        this.currency,
        },
      });
      this.model.unshiftObject(result);
      this.showForm = false;
      this.title = this.description = this.sellerUsername = this.amount = "";
    } catch (e) { popupAjaxError(e); }
    finally { this.submitting = false; }
  }

  // Central action handler — posts to /escrow/:id/:action
  @action async doAction(escrow, act, data = {}) {
    try {
      const result = await ajax(`/escrow/${escrow.id}/${act}`, {
        type: "POST",
        data,
      });
      const idx = this.model.indexOf(escrow);
      if (idx > -1) this.model.replace(idx, 1, [result]);
    } catch (e) { popupAjaxError(e); }
  }

  // Individual actions — names now match the routes exactly
  @action accept(e)  { if (confirm("Accept this escrow?"))                    this.doAction(e, "accept"); }
  @action decline(e) { if (confirm("Decline this escrow?"))                   this.doAction(e, "decline"); }
  @action deliver(e) { if (confirm("Mark as delivered?"))                     this.doAction(e, "deliver"); }   // was mark_delivered
  @action confirm(e) { if (confirm("Confirm delivery and release funds?"))    this.doAction(e, "complete"); }  // was confirm
  @action cancel(e)  { if (confirm("Cancel this escrow?"))                    this.doAction(e, "cancel"); }
  @action dispute(e) {
    const r = prompt("Describe the issue:");
    if (r) this.doAction(e, "dispute", { reason: r });
  }

  // Pay — handles NGN redirect and crypto address display differently
  @action async pay(escrow) {
    try {
      const result = await ajax(`/escrow/${escrow.id}/fund`, { type: "POST" });
      if (result.type === "redirect") {
        window.location.href = result.payment_url;
      } else {
        alert(
          `📤 Send exactly ${result.pay_amount} ${result.pay_currency} to:\n\n` +
          `${result.payment_address}\n\n` +
          `Escrow activates automatically once confirmed on-chain (1–15 min).`
        );
      }
    } catch (e) { popupAjaxError(e); }
  }
}
