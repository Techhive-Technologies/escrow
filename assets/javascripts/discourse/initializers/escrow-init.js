import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "escrow-init",
  initialize() {
    withPluginApi("2.0.0", (api) => {

      // ── Desktop + Mobile: add to sidebar navigation ──
      api.addNavigationBarItem({
        name:        "escrow",
        displayName: "🛡️ Escrow",
        href:        "/my-escrows",
        title:       "My Escrow Deals",
      });

      // ── Desktop header icon (top right, next to notifications) ──
      api.headerIcons.add(
        "escrow",
        <template>
          <li class="header-dropdown-toggle escrow-header-btn">
            
              href="/my-escrows"
              title="My Escrows"
              aria-label="My Escrows"
              class="icon btn-flat"
            >
              🛡️
            </a>
          </li>
        </template>,
        { before: "search" }
      );

      // ── Mobile: add to hamburger menu ──
      api.decorateCookedElement(() => {}, { id: "escrow-mobile" });

    });
  },
};
