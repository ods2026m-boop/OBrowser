using GLib;

namespace ErrorPage {
    public string build_html (string failing_uri, string message) {
        string escaped_uri = Markup.escape_text (failing_uri);
        string escaped_message = Markup.escape_text (message);
        string retry_link = "obrowser://retry?url=" + Uri.escape_string (failing_uri, null, true);
        return "<html><body style='font-family:sans-serif;padding:32px;background:#f8f8f8;color:#222'>"
            + "<h2>Page failed to load</h2>"
            + "<p><b>URL:</b> " + escaped_uri + "</p>"
            + "<p><b>Error:</b> " + escaped_message + "</p>"
            + "<p><a href='" + retry_link + "'>Retry</a></p>"
            + "</body></html>";
    }
}
