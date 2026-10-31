import process from "node:process";

export default defineNuxtConfig({
  compatibilityDate: "2025-07-15",

  icon: {
    serverBundle: {
      collections: ["heroicons"],
    },
  },
  devtools: { enabled: process.env.NODE_ENV === "development" },

  modules: ["@nuxt/ui"],
  css: ["~/assets/css/main.css"],

  app: {
    head: {
      title: "AWS DevOps Platform",
      meta: [
        {
          name: "description",
          content:
            "Production-ready website deployment on AWS with modern DevOps practices",
        },
      ],
      link: [
        { rel: "preconnect", href: "https://fonts.googleapis.com" },
        {
          rel: "stylesheet",
          href: "https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap",
        },
      ],
    },
  },

  colorMode: {
    preference: "light",
    fallback: "light",
    classSuffix: "",
  },

  runtimeConfig: {
    backendUrl: process.env.NUXT_BACKEND_URL || "http://localhost:3002",
    authUrl: process.env.NUXT_AUTH_URL || "http://localhost:3001",
    public: {
      appName: process.env.NUXT_PUBLIC_APP_NAME ?? "DevOps Learning Hub",
      isStaging: process.env.NUXT_PUBLIC_IS_STAGING === "true",
    },
  },
});
