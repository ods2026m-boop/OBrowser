using GLib;

namespace InternalPages {
    public string about_page (AppPaths paths) {
        return "<html><body style='font-family:sans-serif;padding:24px'>"
            + "<h1>OBrowser</h1>"
            + "<p>WebKitGTK-based desktop browser shell.</p>"
            + "<h3>Useful shortcuts</h3>"
            + "<ul>"
            + "<li>Ctrl+T New tab</li>"
            + "<li>Ctrl+W Close tab</li>"
            + "<li>Ctrl+L Focus address bar</li>"
            + "<li>Ctrl+F Find in page</li>"
            + "<li>Ctrl+H History</li>"
            + "<li>Ctrl+J Downloads</li>"
            + "<li>Ctrl+Shift+P Private window</li>"
            + "</ul>"
            + "<h3>Paths</h3>"
            + "<p><b>Config:</b> " + Markup.escape_text (paths.config_dir) + "</p>"
            + "<p><b>Data:</b> " + Markup.escape_text (paths.data_dir) + "</p>"
            + "<p><b>Cache:</b> " + Markup.escape_text (paths.cache_dir) + "</p>"
            + "</body></html>";
    }

    public bool is_internal_uri (string uri) {
        return uri.has_prefix ("obrowser://");
    }

    public string webstore_page (string cards_html) {
        return "<html><body style='font-family:Segoe UI, sans-serif;padding:24px;background:#f6f8fb;color:#1d1f23'>"
            + "<h1 style='margin-top:0'>OBrowser Web Store</h1>"
            + "<p>Install and update plugins with signed package checks.</p>"
            + "<input id='q' placeholder='Search plugins' style='width:100%;max-width:480px;padding:10px;border:1px solid #cfd8e3;border-radius:10px' oninput='f()'/>"
            + "<div style='display:flex;gap:8px;margin:14px 0'>"
            + "<a href='obrowser://webstore/list' style='padding:8px 12px;background:#1a73e8;color:#fff;text-decoration:none;border-radius:8px'>Refresh Catalog</a>"
            + "<a href='obrowser://webstore/check-updates' style='padding:8px 12px;background:#0f9d58;color:#fff;text-decoration:none;border-radius:8px'>Check Updates</a>"
            + "</div>"
            + "<div id='cards' style='display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px'>" + cards_html + "</div>"
            + "<script>function f(){var q=(document.getElementById('q').value||'').toLowerCase();document.querySelectorAll('.card').forEach(function(c){c.style.display=(c.dataset.search.indexOf(q)>=0)?'block':'none';});}</script>"
            + "</body></html>";
    }
}
