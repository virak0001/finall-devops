export default defineNuxtRouteMiddleware(() => {
  const token = useCookie("access_token");
  if (!token.value) {
    return navigateTo("/login");
  }

  try {
    const [, payload] = token.value.split(".");
    const decoded = JSON.parse(atob(payload));
    if (decoded?.role !== "admin") {
      return navigateTo("/dashboard");
    }
  } catch {
    return navigateTo("/login");
  }
});
