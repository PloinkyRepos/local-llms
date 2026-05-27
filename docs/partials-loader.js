document.querySelectorAll('[data-partial]').forEach(async (el) => {
    const src = el.getAttribute('data-partial');
    try {
        const res = await fetch(src);
        if (!res.ok) return;
        const text = await res.text();
        const parser = new DOMParser();
        const doc = parser.parseFromString(text, 'text/html');
        el.replaceChildren(...doc.body.childNodes);
    } catch (_) {}
});
