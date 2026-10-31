export function renderMarkdown(md: string): string {
    // Normalize line endings
    md = md.replace(/\r\n?/g, '\n');

    // Step 1: Extract fenced code blocks into placeholders so their content
    // is never touched by heading / list / paragraph regexes.
    const codeBlocks: string[] = [];
    let src = md.replace(/```(\w*)\n([\s\S]*?)```/g, (_, lang, code) => {
        const escaped = escapeHtml(code.trimEnd());
        const cls = `code-block${lang ? ` lang-${lang}` : ''}`;
        codeBlocks.push(`<pre class="${cls}"><code>${escaped}</code></pre>`);
        return `\x00CODE${codeBlocks.length - 1}\x00`;
    });

    // Step 2: Escape remaining HTML
    let html = escapeHtml(src);

    // Inline code (after escaping)
    html = html.replace(/`([^`]+)`/g, (_, c) => `<code class="inline-code">${escapeHtml(c)}</code>`);

    // H1–H3 with ids (safe — code blocks are placeholders now)
    html = html.replace(/^### (.+)$/gm, (_, t) => `<h3 id="${slugify(t)}">${t}</h3>`);
    html = html.replace(/^## (.+)$/gm,  (_, t) => `<h2 id="${slugify(t)}">${t}</h2>`);
    html = html.replace(/^# (.+)$/gm,   (_, t) => `<h1 id="${slugify(t)}">${t}</h1>`);

    // Bold / italic
    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');

    // Links
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" class="text-teal-700 underline underline-offset-2 hover:text-teal-900">$1</a>');

    // Tables
    html = html.replace(
        /(\|.+\|\n)(\|[-: |]+\|\n)((?:\|.+\|\n?)*)/g,
        (_m, header, _sep, body) => {
            const th = header.trim().split('|').filter(Boolean)
                .map((c: string) => `<th>${c.trim()}</th>`).join('');
            const rows = body.trim().split('\n')
                .map((row: string) =>
                    '<tr>' + row.split('|').filter(Boolean)
                        .map((c: string) => `<td>${c.trim()}</td>`).join('') + '</tr>',
                ).join('');
            return `<table><thead><tr>${th}</tr></thead><tbody>${rows}</tbody></table>`;
        },
    );

    // Unordered lists
    html = html.replace(/^[-*] (.+)$/gm, '<li>$1</li>');
    html = html.replace(/(<li>.*<\/li>\n?)+/g, (m) => `<ul>${m}</ul>`);

    // Paragraphs
    const lines = html.split('\n');
    const out: string[] = [];
    for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) { out.push(''); continue; }
        if (/^<(h[1-6]|ul|ol|li|pre|table|thead|tbody|tr|th|td)/.test(trimmed)) {
            out.push(trimmed);
        } else {
            out.push(`<p>${trimmed}</p>`);
        }
    }
    html = out.join('\n');

    // Step 3: Restore code blocks
    html = html.replace(/\x00CODE(\d+)\x00/g, (_, i) => codeBlocks[Number(i)] ?? '');

    return html;
}

export function escapeHtml(s: string): string {
    return s
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

export function slugify(text: string): string {
    return text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}
