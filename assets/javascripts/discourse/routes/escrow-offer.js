import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class EscrowOfferRoute extends DiscourseRoute {
  titleToken() {
    return "Escrow Offer";
  }

  async model(params) {
    const data = await ajax(`/escrow/${params.id}`);
    return data;
  }
}
