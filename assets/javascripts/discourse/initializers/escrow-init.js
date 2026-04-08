import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "escrow-init",
  initialize() {
    withPluginApi("0.8.31", (api) => {

      // Add "Escrow" to the top navigation menu
      api.decorateWidget("header-icons:before", (helper) => {
        return helper.h(
          "li.header-escrow-icon",
          helper.h(
            "a",
            {
              href: "/escrow-page",
              title: "Escrow",
              className: "icon btn-flat",
            },
            helper.h("span", { className: "d-icon d-icon-shield-alt" }, "🛡")
          )
        );
      });
    });
  },
};
