import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "escrow-init",
  initialize() {
    withPluginApi("2.0.0", (api) => {

      // Add "Escrow" link to the sidebar or top nav
      api.addNavigationBarItem({
        name: "escrow",
        displayName: "🛡️ Escrow",
        href: "/my-escrows",
        title: "Escrow Deals",
      });

    });
  },
};
