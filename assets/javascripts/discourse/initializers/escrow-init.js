import { withPluginApi } from "discourse/lib/plugin-api";
import MyEscrowsRoute from "../routes/my-escrows";
import MyEscrowsController from "../controllers/my-escrows";

export default {
  name: "escrow-init",
  initialize(container) {
    withPluginApi("2.0.0", (api) => {

      // Register the page route
      api.addNavigationBarItem({
        name:        "escrow",
        displayName: "🛡️ Escrow",
        href:        "/my-escrows",
        title:       "My Escrow Deals",
      });

    });

    // Register route and controller
    container.register("route:my-escrows",       MyEscrowsRoute);
    container.register("controller:my-escrows",  MyEscrowsController);
  },
};
