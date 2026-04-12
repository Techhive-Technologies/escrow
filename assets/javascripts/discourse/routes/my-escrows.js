import DiscourseRoute from "discourse/routes/discourse";

export default class MyEscrowsRoute extends DiscourseRoute {
  titleToken() {
    return "My Escrows";
  }

  // Template loads its own data — route just sets the title
  model() {
    return [];
  }
}
