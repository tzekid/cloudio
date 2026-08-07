(function () {
  "use strict";

  function byId(id) {
    return document.getElementById(id);
  }

  function mount() {
    const shell = byId("app-shell");
    const content = byId("page-content");
    const sidebar = byId("primary-sidebar");
    const menu = shell && shell.querySelector(".menu-button");
    const scrim = document.querySelector(".sidebar-scrim");
    if (!shell || !content || !sidebar || !menu || !scrim) {
      throw new Error("Incomplete server-rendered application shell");
    }

    content.classList.add("page-content");
    content.tabIndex = -1;

    function setMenu(open, restoreFocus) {
      sidebar.dataset.open = String(open);
      scrim.dataset.open = String(open);
      menu.setAttribute("aria-expanded", String(open));
      if (open) {
        const current = sidebar.querySelector('[aria-current="page"]') || sidebar.querySelector("a");
        if (current) current.focus();
      } else if (restoreFocus) {
        menu.focus();
      }
    }

    menu.addEventListener("click", function () {
      setMenu(sidebar.dataset.open !== "true", true);
    });
    scrim.addEventListener("click", function () {
      setMenu(false, true);
    });
    sidebar.addEventListener("click", function (event) {
      if (event.target.closest("a") && window.matchMedia("(max-width: 720px)").matches) {
        setMenu(false, false);
      }
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && sidebar.dataset.open === "true") setMenu(false, true);
    });
  }

  mount();
})();
