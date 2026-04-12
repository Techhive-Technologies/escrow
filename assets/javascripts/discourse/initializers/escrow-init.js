import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "escrow-init",
  initialize() {
    withPluginApi("0.8.31", (api) => {
      api.addNavigationBarItem({
        name:        "escrow",
        displayName: "🛡️ Escrow",
        href:        "/my-escrows",
        title:       "My Escrow Deals",
      });
    });
  },
};
