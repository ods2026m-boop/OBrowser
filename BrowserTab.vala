using Gtk;
using WebKit;
using GLib;
using Gdk;

public class BrowserTab : Box {
    public signal void title_changed ();
    public signal void uri_changed ();
    public signal void loading_changed ();
    public signal void page_loaded (string uri, string title);
    public signal BrowserTab create_tab_requested (string target_uri);
    public signal bool internal_uri_requested (string uri);
    public signal bool permission_requested (PermissionRequest request, string origin);
    public signal void favicon_changed ();
    public signal void security_blocked (string uri, string reason);

    public WebView webview { get; private set; }
    public bool is_private { get; private set; }
    public Gdk.Pixbuf? favicon { get; private set; default = null; }
    private SecurityManager security_manager;

    private string last_error_message = "";
    private string last_failing_uri = "";

    public BrowserTab (WebContext context, WebKit.Settings settings, SecurityManager security_manager, bool is_private = false) {
        Object (orientation: Orientation.VERTICAL, spacing: 0);
        this.is_private = is_private;
        this.security_manager = security_manager;

        var scroll = new ScrolledWindow (null, null);
        scroll.hexpand = true;
        scroll.vexpand = true;
        pack_start (scroll, true, true, 0);

        webview = new WebView.with_context (context);
        webview.set_settings (settings);
        webview.hexpand = true;
        webview.vexpand = true;
        scroll.add (webview);

        webview.notify["title"].connect (() => { title_changed (); });
        webview.notify["uri"].connect (() => { uri_changed (); });
        webview.notify["estimated-load-progress"].connect (() => { loading_changed (); });
        webview.notify["favicon"].connect (() => {
            update_favicon ();
            title_changed ();
        });

        webview.load_changed.connect ((event) => {
            if (event == LoadEvent.STARTED) {
                last_error_message = "";
            }
            if (event == LoadEvent.FINISHED) {
                update_favicon ();
                page_loaded (current_uri (), display_title ());
            }
            uri_changed ();
            loading_changed ();
        });

        webview.load_failed.connect ((event, failing_uri, error) => {
            if (failing_uri.has_prefix ("obrowser://")) {
                return false;
            }

            if (error != null && error.domain == WebKit.NetworkError.quark () && error.code == WebKit.NetworkError.CANCELLED) {
                last_error_message = "";
                loading_changed ();
                title_changed ();
                return false;
            }

            last_error_message = error != null ? error.message : "Failed to load page";
            last_failing_uri = failing_uri;
            load_error_page (failing_uri, last_error_message);
            title_changed ();
            loading_changed ();
            return true;
        });

        webview.load_failed_with_tls_errors.connect ((failing_uri, certificate, errors) => {
            last_error_message = "TLS error: %s".printf (errors.to_string ());
            last_failing_uri = failing_uri;
            load_error_page (failing_uri, last_error_message);
            title_changed ();
            loading_changed ();
            return true;
        });

        webview.decide_policy.connect ((decision, type) => {
            string target = "";
            if (type == PolicyDecisionType.NAVIGATION_ACTION) {
                var navigation = decision as NavigationPolicyDecision;
                if (navigation != null) {
                    URIRequest? request = navigation.get_navigation_action ().get_request ();
                    target = request != null ? (request.get_uri () ?? "") : "";
                }
            } else if (type == PolicyDecisionType.NEW_WINDOW_ACTION) {
                var navigation = decision as NavigationPolicyDecision;
                if (navigation != null) {
                    URIRequest? request = navigation.get_navigation_action ().get_request ();
                    target = request != null ? (request.get_uri () ?? "") : "";
                }
            } else if (type == PolicyDecisionType.RESPONSE) {
                var response = decision as ResponsePolicyDecision;
                if (response != null) {
                    if (!response.is_main_frame_main_resource ()) {
                        return false;
                    }
                    URIRequest? request = response.get_request ();
                    target = request != null ? (request.get_uri () ?? "") : "";
                }
            } else {
                return false;
            }

            if (target == "") {
                return false;
            }

            if (target.has_prefix ("obrowser://")) {
                if (internal_uri_requested (target)) {
                    decision.ignore ();
                    return true;
                }
            }

            string reason = "";
            if (security_manager.should_block (target, current_uri (), out reason)) {
                last_error_message = "Blocked by security policy: " + reason;
                last_failing_uri = target;
                security_blocked (target, reason);
                load_error_page (target, last_error_message);
                decision.ignore ();
                loading_changed ();
                title_changed ();
                return true;
            }
            return false;
        });

        webview.create.connect ((navigation_action) => {
            string requested_uri = "";
            URIRequest? request = navigation_action.get_request ();
            if (request != null && request.get_uri () != null) {
                requested_uri = request.get_uri ();
            }
            var new_tab = create_tab_requested (requested_uri);
            return new_tab.webview;
        });

        webview.permission_request.connect ((request) => {
            string origin = current_uri ();
            return permission_requested (request, origin);
        });

        show_all ();
    }

    public void apply_browser_settings (BrowserSettings settings_values) {
        WebKit.Settings? settings = webview.get_settings ();
        if (settings == null) {
            return;
        }
        settings.enable_javascript = settings_values.enable_javascript;
        settings.auto_load_images = settings_values.enable_images;
        settings.enable_developer_extras = settings_values.enable_developer_tools;
        settings.enable_write_console_messages_to_stdout = settings_values.enable_developer_tools;
        settings.user_agent = settings_values.user_agent.strip () != "" ? settings_values.user_agent : null;
        webview.set_zoom_level (settings_values.default_zoom_level);
    }

    public void load_target (string target) {
        string clean = target.strip ();
        if (clean == "") {
            clean = "about:blank";
        }

        if (clean == "about:blank") {
            webview.load_uri (clean);
            return;
        }

        if (clean.has_prefix ("obrowser://about")) {
            load_html_content (InternalPages.about_page (new AppPaths ()), "obrowser://about");
            return;
        }

        string reason = "";
        if (security_manager.should_block (clean, current_uri (), out reason)) {
            last_error_message = "Blocked by security policy: " + reason;
            last_failing_uri = clean;
            security_blocked (clean, reason);
            load_error_page (clean, last_error_message);
            loading_changed ();
            title_changed ();
            return;
        }

        webview.load_uri (clean);
    }

    public void load_html_content (string html, string base_uri) {
        webview.load_html (html, base_uri);
    }

    public void go_back_if_possible () { if (webview.can_go_back ()) { webview.go_back (); } }
    public void go_forward_if_possible () { if (webview.can_go_forward ()) { webview.go_forward (); } }
    public void reload_tab () { webview.reload (); }
    public void stop_loading_tab () { webview.stop_loading (); }

    public string current_uri () {
        string? uri = webview.get_uri ();
        return uri ?? "";
    }

    public string retry_uri () {
        return last_failing_uri.strip () != "" ? last_failing_uri : current_uri ();
    }

    public string display_title () {
        if (last_error_message != "") {
            return "Load Error";
        }
        string? title = webview.get_title ();
        if (title != null && title.strip () != "") {
            return title;
        }
        string uri = current_uri ();
        return uri != "" ? uri : "New Tab";
    }

    public string status_text () {
        if (last_error_message != "") {
            return last_error_message;
        }
        if (!webview.is_loading) {
            return "Done";
        }
        return "Loading %d%%".printf ((int) (webview.estimated_load_progress * 100.0));
    }

    public bool has_error () {
        return last_error_message != "";
    }

    private void load_error_page (string uri, string message) {
        webview.load_html (ErrorPage.build_html (uri, message), "obrowser://error");
    }

    private void update_favicon () {
        if (is_private) {
            favicon = null;
            favicon_changed ();
            return;
        }

        string uri = current_uri ();
        if (uri.strip () == "" || uri.has_prefix ("obrowser://")) {
            favicon = null;
            favicon_changed ();
            return;
        }

        WebContext? context = webview.get_context ();
        if (context == null) {
            return;
        }

        context.get_favicon_database ().get_favicon.begin (uri, null, (obj, res) => {
            try {
                Cairo.Surface surface = context.get_favicon_database ().get_favicon.end (res);
                favicon = OBrowserUtils.pixbuf_from_surface (surface);
            } catch (Error error) {
                favicon = null;
            }
            favicon_changed ();
        });
    }
}
