import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class MyEscrowsRoute extends DiscourseRoute {
  // Sets the page title in the browser tab
  titleToken() {
    return "My Escrows";
  }

  async model() {
    const data = await ajax("/escrow/");
    return data.transactions || [];
  }
}
