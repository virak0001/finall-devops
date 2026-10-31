/**
 * Single source of truth for the public site's navigation and social links.
 * Used by the `site` layout and by any page that renders them inline.
 */
export function useSiteNav() {
    const navLinks = [
        { label: 'Home', to: '/' },
        { label: 'Learn', to: '/learn' },
        { label: 'Playbooks', to: '/playbooks' },
        { label: 'Resources', to: '/resources' },
        { label: 'Blog', to: '/blog' },
        { label: 'About', to: '/about' },
    ];

    // Heroicons only: brand marks would need @iconify-json/simple-icons, which
    // is not installed and cannot currently be fetched from the registry.
    // TODO: point these at your real profiles.
    const socialLinks = [
        { label: 'GitHub', icon: 'i-heroicons-code-bracket-square', to: 'https://github.com/virak-01' },
        { label: 'LinkedIn', icon: 'i-heroicons-briefcase', to: 'https://linkedin.com/' },
        { label: 'Email', icon: 'i-heroicons-envelope', to: 'mailto:ran@example.com' },
    ];

    return { navLinks, socialLinks };
}
