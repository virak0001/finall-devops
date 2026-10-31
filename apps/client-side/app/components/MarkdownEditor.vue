<template>
    <div class="flex flex-col flex-1 min-h-0 rounded-xl border border-default overflow-hidden">
        <!-- Tab bar + toolbar -->
        <div
            class="flex items-center justify-between gap-2 px-2 pt-0.5 border-b border-default bg-elevated/40 shrink-0">
            <!-- Write / Preview tabs -->
            <div class="flex">
                <button :class="['px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors',
                    activeTab === 'write'
                        ? 'border-primary text-highlighted'
                        : 'border-transparent text-muted hover:text-highlighted']" @click="activeTab = 'write'">Write</button>
                <button :class="['px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors',
                    activeTab === 'preview'
                        ? 'border-primary text-highlighted'
                        : 'border-transparent text-muted hover:text-highlighted']"
                    @click="activeTab = 'preview'">Preview</button>
            </div>

            <!-- Formatting toolbar (write mode only) -->
            <div v-if="activeTab === 'write'" class="flex items-center gap-0.5 pr-1">
                <template v-for="item in toolbar" :key="item.key">
                    <div v-if="item.separator" class="h-4 border-l border-default mx-0.5" />
                    <button v-else :title="item.label"
                        class="flex items-center justify-center h-7 min-w-7 rounded px-1.5 text-muted hover:text-highlighted hover:bg-elevated transition-colors"
                        @mousedown.prevent="applyFormat(item)">
                        <UIcon v-if="item.icon" :name="item.icon" class="size-4" />
                        <span v-else :class="['text-xs leading-none select-none', item.textClass]">{{ item.text
                            }}</span>
                    </button>
                </template>
            </div>
        </div>

        <!-- Write: textarea -->
        <textarea v-if="activeTab === 'write'" ref="editorRef" :value="modelValue"
            class="flex-1 w-full bg-transparent px-4 py-3 font-mono text-sm text-highlighted resize-none focus:outline-none"
            :style="{ minHeight: minHeight }" :placeholder="placeholder" spellcheck="false"
            @input="emit('update:modelValue', ($event.target as HTMLTextAreaElement).value)"
            @keydown="handleEditorKeydown" />

        <!-- Preview -->
        <div v-else class="flex-1 overflow-y-auto px-6 py-5">
            <div v-if="modelValue" class="md-prose" v-html="renderedPreview" />
            <p v-else class="text-sm text-muted italic">Nothing to preview.</p>
        </div>
    </div>
</template>

<script setup lang="ts">
interface Props {
    modelValue: string;
    placeholder?: string;
    minHeight?: string;
}

const props = withDefaults(defineProps<Props>(), {
    placeholder: 'Write content in Markdown…',
    minHeight: '460px',
});

const emit = defineEmits<{
    'update:modelValue': [value: string];
}>();

const activeTab = ref<'write' | 'preview'>('write');
const editorRef = ref<HTMLTextAreaElement | null>(null);

const renderedPreview = computed(() => renderMarkdown(props.modelValue));

// ── Toolbar definition ────────────────────────────────────────────────────────

interface ToolbarItem {
    key: string;
    label?: string;
    icon?: string;
    text?: string;
    textClass?: string;
    separator?: boolean;
    before?: string;
    after?: string;
    placeholder?: string;
    prefix?: string;
    snippet?: string;
}

const toolbar: ToolbarItem[] = [
    { key: 'bold', label: 'Bold (Ctrl+B)', text: 'B', textClass: 'font-bold', before: '**', after: '**', placeholder: 'bold text' },
    { key: 'italic', label: 'Italic (Ctrl+I)', text: 'I', textClass: 'italic', before: '*', after: '*', placeholder: 'italic text' },
    { key: 'sep1', separator: true },
    { key: 'h1', label: 'Heading 1', text: 'H1', textClass: 'font-bold text-[11px]', prefix: '# ' },
    { key: 'h2', label: 'Heading 2', text: 'H2', textClass: 'font-bold text-[11px]', prefix: '## ' },
    { key: 'h3', label: 'Heading 3', text: 'H3', textClass: 'font-bold text-[11px]', prefix: '### ' },
    { key: 'sep2', separator: true },
    { key: 'quote', label: 'Blockquote', icon: 'i-heroicons-chat-bubble-left-ellipsis', prefix: '> ' },
    { key: 'code', label: 'Inline code', icon: 'i-heroicons-code-bracket', before: '`', after: '`', placeholder: 'code' },
    { key: 'codeblock', label: 'Code block', icon: 'i-heroicons-command-line', snippet: '```\ncode\n```' },
    { key: 'sep3', separator: true },
    { key: 'link', label: 'Link (Ctrl+K)', icon: 'i-heroicons-link', before: '[', after: '](url)', placeholder: 'link text' },
    { key: 'ul', label: 'Bulleted list', icon: 'i-heroicons-list-bullet', prefix: '- ' },
    { key: 'table', label: 'Table', icon: 'i-heroicons-table-cells', snippet: '| Header | Header |\n|--------|--------|\n| Cell   | Cell   |\n' },
];

// ── Format insertion ──────────────────────────────────────────────────────────

function applyFormat(item: ToolbarItem) {
    const ta = editorRef.value;
    if (!ta || item.separator) return;

    const start = ta.selectionStart ?? 0;
    const end = ta.selectionEnd ?? 0;
    const val = props.modelValue;
    const selected = val.slice(start, end);

    let newContent: string;
    let newStart: number;
    let newEnd: number;

    if (item.snippet) {
        const nl = start > 0 && val[start - 1] !== '\n' ? '\n' : '';
        const insert = nl + item.snippet + '\n';
        newContent = val.slice(0, start) + insert + val.slice(end);
        newStart = start + insert.length;
        newEnd = newStart;
    } else if (item.prefix) {
        const lineStart = val.lastIndexOf('\n', start - 1) + 1;
        newContent = val.slice(0, lineStart) + item.prefix + val.slice(lineStart);
        newStart = start + item.prefix.length;
        newEnd = end + item.prefix.length;
    } else if (item.before !== undefined) {
        const text = selected || item.placeholder || '';
        newContent = val.slice(0, start) + item.before + text + (item.after ?? '') + val.slice(end);
        newStart = start + item.before.length;
        newEnd = newStart + text.length;
    } else {
        return;
    }

    emit('update:modelValue', newContent);
    nextTick(() => {
        ta.focus();
        ta.setSelectionRange(newStart, newEnd);
    });
}

function handleEditorKeydown(e: KeyboardEvent) {
    if (!(e.ctrlKey || e.metaKey)) return;
    const shortcuts: Record<string, string> = { b: 'bold', i: 'italic', k: 'link' };
    const key = shortcuts[e.key];
    if (key) {
        e.preventDefault();
        const item = toolbar.find(t => t.key === key);
        if (item) applyFormat(item);
    }
}

// renderMarkdown, escapeHtml, slugify are auto-imported from ~/utils/markdown.ts
</script>

<style scoped>
.md-prose :deep(h1),
.md-prose :deep(h2),
.md-prose :deep(h3) {
    font-weight: 700;
    color: var(--ui-text-highlighted);
    margin: 1.5rem 0 0.6rem;
    line-height: 1.3;
}

.md-prose :deep(h1) {
    font-size: 1.25rem;
    border-bottom: 1px solid var(--ui-border);
    padding-bottom: 0.4rem;
}

.md-prose :deep(h2) {
    font-size: 1.05rem;
}

.md-prose :deep(h3) {
    font-size: 0.95rem;
}

.md-prose :deep(p) {
    font-size: 0.9rem;
    color: var(--ui-text);
    line-height: 1.75;
    margin: 0 0 0.9rem;
}

.md-prose :deep(ul) {
    list-style: disc;
    padding-left: 1.5rem;
    margin: 0 0 1rem;
}

.md-prose :deep(li) {
    font-size: 0.9rem;
    color: var(--ui-text);
    line-height: 1.65;
    margin-bottom: 0.25rem;
}

.md-prose :deep(table) {
    width: 100%;
    border-collapse: collapse;
    margin: 1rem 0;
    font-size: 0.875rem;
}

.md-prose :deep(th) {
    background: var(--ui-bg-elevated);
    color: var(--ui-text-highlighted);
    font-weight: 600;
    padding: 0.5rem 0.75rem;
    text-align: left;
    border-bottom: 1px solid var(--ui-border);
}

.md-prose :deep(td) {
    padding: 0.45rem 0.75rem;
    border-bottom: 1px solid var(--ui-border-muted, var(--ui-border));
    color: var(--ui-text);
    vertical-align: top;
}

.md-prose :deep(pre.code-block) {
    background: #0d1117;
    color: #e6edf3;
    border: 1px solid #30363d;
    border-radius: 0.5rem;
    padding: 1rem 1.25rem;
    overflow-x: auto;
    overflow-y: auto;
    max-height: 480px;
    margin: 1rem 0;
    font-size: 0.85rem;
    white-space: pre;
    min-width: 0;
}

.md-prose :deep(code) {
    font-family: 'IBM Plex Mono', 'Fira Code', ui-monospace, monospace;
    font-size: 0.85em;
    white-space: pre;
    color: inherit;
}

.md-prose :deep(.inline-code) {
    background: color-mix(in srgb, var(--ui-primary) 10%, transparent);
    color: var(--ui-primary);
    padding: 0.1em 0.35em;
    border-radius: 0.25rem;
}

.md-prose :deep(strong) {
    color: var(--ui-text-highlighted);
    font-weight: 600;
}

.md-prose :deep(em) {
    font-style: italic;
}
</style>
