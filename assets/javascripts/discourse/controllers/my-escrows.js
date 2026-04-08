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
  @tracked currency = "USD";
  currencies = ["USD", "NGN", "USDT", "USDC"];

  @action toggleForm() { this.showForm = !this.showForm; }

  @action async create() {
    if (!this.title || !this.sellerUsername || !this.amount) return;
    this.submitting = true;
    try {
      const result = await ajax("/krabit/escrows.json", {
        type: "POST",
        data: { escrow: { title: this.title, description: this.description,
          seller_username: this.sellerUsername, amount: this.amount, currency: this.currency } },
      });
      this.model.unshiftObject(result);
      this.showForm = false;
      this.title = this.description = this.sellerUsername = this.amount = "";
    } catch(e) { popupAjaxError(e); }
    finally { this.submitting = false; }
  }

  @action async doAction(escrow, act, data = {}) {
    try {
      const result = await ajax(`/krabit/escrows/${escrow.id}/${act}.json`, { type: "POST", data });
      const idx = this.model.indexOf(escrow);
      if (idx > -1) this.model.replace(idx, 1, [result]);
    } catch(e) { popupAjaxError(e); }
  }

  @action accept(e)  { if (confirm("Accept this escrow?")) this.doAction(e, "accept"); }
  @action decline(e) { if (confirm("Decline?")) this.doAction(e, "decline"); }
  @action deliver(e) { if (confirm("Mark as delivered?")) this.doAction(e, "mark_delivered"); }
  @action confirm(e) { if (confirm("Confirm delivery and release funds?")) this.doAction(e, "confirm"); }
  @action cancel(e)  { if (confirm("Cancel this escrow?")) this.doAction(e, "cancel"); }
  @action dispute(e) { const r = prompt("Describe the issue:"); if (r) this.doAction(e, "dispute", { reason: r }); }
}
