import { withPluginApi } from "discourse/lib/plugin-api";
export default {
  name: "krabit-escrow",
  initialize() {
    withPluginApi("0.8.31", (api) => {
      api.addQuickAccessProfileItem({ icon: "shield-alt", href: "/my/escrows", content: "My Escrows" });
    });
  },
};
