import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class MyEscrowsRoute extends Route {
  async model() {
    const data = await ajax("/krabit/escrows.json");
    return data.escrows || [];
  }
}
