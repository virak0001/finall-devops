export default defineAppConfig({
  ui: {
    colors: {
      primary: "teal",
      neutral: "slate",
    },

    // Nuxt UI's built-in icons default to the `lucide` collection, but
    // @iconify-json/lucide is in neither package.json nor package-lock.json — so
    // `npm ci` (Dockerfile + CI) has never installed it, and every one of these
    // has been rendering as an empty box in production.
    //
    // Remapped to heroicons, the collection that IS installed and listed in
    // nuxt.config's `icon.serverBundle.collections`. If lucide is ever added to
    // package.json, this whole block can be deleted.
    icons: {
      arrowDown: "i-heroicons-arrow-down",
      arrowLeft: "i-heroicons-arrow-left",
      arrowRight: "i-heroicons-arrow-right",
      arrowUp: "i-heroicons-arrow-up",
      caution: "i-heroicons-exclamation-circle",
      check: "i-heroicons-check",
      chevronDoubleLeft: "i-heroicons-chevron-double-left",
      chevronDoubleRight: "i-heroicons-chevron-double-right",
      chevronDown: "i-heroicons-chevron-down",
      chevronLeft: "i-heroicons-chevron-left",
      chevronRight: "i-heroicons-chevron-right",
      chevronUp: "i-heroicons-chevron-up",
      close: "i-heroicons-x-mark",
      copy: "i-heroicons-clipboard-document",
      copyCheck: "i-heroicons-clipboard-document-check",
      dark: "i-heroicons-moon",
      drag: "i-heroicons-bars-3",
      ellipsis: "i-heroicons-ellipsis-horizontal",
      error: "i-heroicons-x-circle",
      external: "i-heroicons-arrow-top-right-on-square",
      eye: "i-heroicons-eye",
      eyeOff: "i-heroicons-eye-slash",
      file: "i-heroicons-document",
      folder: "i-heroicons-folder",
      folderOpen: "i-heroicons-folder-open",
      hash: "i-heroicons-hashtag",
      info: "i-heroicons-information-circle",
      light: "i-heroicons-sun",
      loading: "i-heroicons-arrow-path",
      menu: "i-heroicons-bars-3",
      minus: "i-heroicons-minus",
      panelClose: "i-heroicons-chevron-double-left",
      panelOpen: "i-heroicons-chevron-double-right",
      plus: "i-heroicons-plus",
      reload: "i-heroicons-arrow-path",
      search: "i-heroicons-magnifying-glass",
      stop: "i-heroicons-stop",
      success: "i-heroicons-check-circle",
      system: "i-heroicons-computer-desktop",
      tip: "i-heroicons-light-bulb",
      upload: "i-heroicons-arrow-up-tray",
      warning: "i-heroicons-exclamation-triangle",
    },
  },
});
