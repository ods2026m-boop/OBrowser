using GLib;

public class SettingsManager : Object {
    private string path;
    private BrowserSettings values;
    private AppPaths app_paths;
    private bool use_keyring;

    public signal void changed (BrowserSettings settings);

    public SettingsManager (AppPaths paths) {
        app_paths = paths;
        path = paths.settings_file ();
        values = new BrowserSettings ();
        values.download_directory = paths.default_download_dir ();
        use_keyring = OBrowserSecret.backend_available ();
        load ();
    }

    public BrowserSettings snapshot () {
        return values;
    }

    public string home_page { get { return values.home_page; } }
    public string search_engine_id { get { return values.search_engine_id; } }
    public StartupBehavior startup_behavior { get { return values.startup_behavior; } }
    public bool restore_session { get { return values.restore_session; } }
    public string download_directory { get { return values.download_directory; } }
    public bool ask_download_location { get { return values.ask_download_location; } }
    public double default_zoom_level { get { return values.default_zoom_level; } }
    public bool show_status_bar { get { return values.show_status_bar; } }
    public bool show_bookmarks_bar { get { return values.show_bookmarks_bar; } }
    public string ui_theme { get { return values.ui_theme; } }
    public bool save_history { get { return values.save_history; } }
    public bool enable_javascript { get { return values.enable_javascript; } }
    public bool enable_images { get { return values.enable_images; } }
    public bool enable_developer_tools { get { return values.enable_developer_tools; } }
    public string user_agent { get { return values.user_agent; } }
    public string update_manifest_url { get { return values.update_manifest_url; } }
    public string update_channel { get { return values.update_channel; } }
    public string update_pinned_pubkey { get { return values.update_pinned_pubkey; } }
    public string update_next_pubkey { get { return values.update_next_pubkey; } }
    public bool update_allow_key_rotation { get { return values.update_allow_key_rotation; } }
    public string sync_endpoint { get { return values.sync_endpoint; } }
    public string sync_token { get { return values.sync_token; } }
    public string crash_endpoint { get { return values.crash_endpoint; } }
    public string crash_token { get { return values.crash_token; } }

    public void load () {
        values = new BrowserSettings ();
        values.download_directory = app_paths.default_download_dir ();
        KeyFile key_file = OBrowserUtils.load_key_file_safe (path);

        values.home_page = OBrowserUtils.normalize_home_page (get_string (key_file, "general", "home_page", values.home_page), "about:blank");
        if (values.home_page == "https://duckduckgo.com/" || values.home_page == "https://duckduckgo.com") {
            values.home_page = "https://www.google.com/";
        }
        values.search_engine_id = get_string (key_file, "general", "search_engine_id", values.search_engine_id);
        if (values.search_engine_id.strip () == "" || values.search_engine_id == "duckduckgo") {
            values.search_engine_id = "google";
        }
        values.startup_behavior = StartupBehavior.from_key (get_string (key_file, "general", "startup_behavior", values.startup_behavior.to_key ()));
        values.restore_session = get_bool (key_file, "general", "restore_session", values.restore_session);
        values.download_directory = get_string (key_file, "downloads", "directory", values.download_directory);
        values.ask_download_location = get_bool (key_file, "downloads", "ask_each_time", values.ask_download_location);
        values.default_zoom_level = get_double (key_file, "appearance", "default_zoom_level", values.default_zoom_level);
        values.show_status_bar = get_bool (key_file, "appearance", "show_status_bar", values.show_status_bar);
        values.show_bookmarks_bar = get_bool (key_file, "appearance", "show_bookmarks_bar", values.show_bookmarks_bar);
        values.ui_theme = get_string (key_file, "appearance", "ui_theme", values.ui_theme).down ();
        if (values.ui_theme != "light" && values.ui_theme != "dark" && values.ui_theme != "holographic" && values.ui_theme != "firefox") {
            values.ui_theme = "light";
        }
        values.save_history = get_bool (key_file, "privacy", "save_history", values.save_history);
        values.enable_javascript = get_bool (key_file, "content", "enable_javascript", values.enable_javascript);
        values.enable_images = get_bool (key_file, "content", "enable_images", values.enable_images);
        values.enable_developer_tools = get_bool (key_file, "content", "enable_developer_tools", values.enable_developer_tools);
        values.user_agent = get_string (key_file, "content", "user_agent", values.user_agent);
        values.update_manifest_url = get_string (key_file, "integrations", "update_manifest_url", values.update_manifest_url);
        values.update_channel = get_string (key_file, "integrations", "update_channel", values.update_channel);
        values.update_pinned_pubkey = get_string (key_file, "integrations", "update_pinned_pubkey", values.update_pinned_pubkey);
        values.update_next_pubkey = get_string (key_file, "integrations", "update_next_pubkey", values.update_next_pubkey);
        values.update_allow_key_rotation = get_bool (key_file, "integrations", "update_allow_key_rotation", values.update_allow_key_rotation);
        values.sync_endpoint = get_string (key_file, "integrations", "sync_endpoint", values.sync_endpoint);
        values.crash_endpoint = get_string (key_file, "integrations", "crash_endpoint", values.crash_endpoint);
        if (use_keyring) {
            values.sync_token = OBrowserSecret.load ("token", "sync") ?? "";
            values.crash_token = OBrowserSecret.load ("token", "crash") ?? "";
        }

        if (values.download_directory.strip () == "") {
            values.download_directory = app_paths.default_download_dir ();
        }
        OBrowserUtils.ensure_directory (values.download_directory);
        save (false);
    }

    public void update (BrowserSettings updated) {
        values = updated;
        values.home_page = OBrowserUtils.normalize_home_page (updated.home_page, "about:blank");
        values.download_directory = updated.download_directory.strip () != "" ? updated.download_directory : app_paths.default_download_dir ();
        if (values.default_zoom_level < 0.3) {
            values.default_zoom_level = 0.3;
        }
        if (values.default_zoom_level > 5.0) {
            values.default_zoom_level = 5.0;
        }
        values.restore_session = updated.restore_session;
        OBrowserUtils.ensure_directory (values.download_directory);
        save (true);
    }

    private void save (bool emit_signal) {
        var key_file = new KeyFile ();
        key_file.set_string ("general", "home_page", values.home_page);
        key_file.set_string ("general", "search_engine_id", values.search_engine_id);
        key_file.set_string ("general", "startup_behavior", values.startup_behavior.to_key ());
        key_file.set_boolean ("general", "restore_session", values.restore_session);
        key_file.set_string ("downloads", "directory", values.download_directory);
        key_file.set_boolean ("downloads", "ask_each_time", values.ask_download_location);
        key_file.set_double ("appearance", "default_zoom_level", values.default_zoom_level);
        key_file.set_boolean ("appearance", "show_status_bar", values.show_status_bar);
        key_file.set_boolean ("appearance", "show_bookmarks_bar", values.show_bookmarks_bar);
        key_file.set_string ("appearance", "ui_theme", values.ui_theme);
        key_file.set_boolean ("privacy", "save_history", values.save_history);
        key_file.set_boolean ("content", "enable_javascript", values.enable_javascript);
        key_file.set_boolean ("content", "enable_images", values.enable_images);
        key_file.set_boolean ("content", "enable_developer_tools", values.enable_developer_tools);
        key_file.set_string ("content", "user_agent", values.user_agent);
        key_file.set_string ("integrations", "update_manifest_url", values.update_manifest_url);
        key_file.set_string ("integrations", "update_channel", values.update_channel);
        key_file.set_string ("integrations", "update_pinned_pubkey", values.update_pinned_pubkey);
        key_file.set_string ("integrations", "update_next_pubkey", values.update_next_pubkey);
        key_file.set_boolean ("integrations", "update_allow_key_rotation", values.update_allow_key_rotation);
        key_file.set_string ("integrations", "sync_endpoint", values.sync_endpoint);
        key_file.set_string ("integrations", "crash_endpoint", values.crash_endpoint);
        if (use_keyring) {
            if (values.sync_token.strip () != "") {
                OBrowserSecret.store ("token", "sync", values.sync_token, "OBrowser sync token");
            } else {
                OBrowserSecret.clear ("token", "sync");
            }
            if (values.crash_token.strip () != "") {
                OBrowserSecret.store ("token", "crash", values.crash_token, "OBrowser crash token");
            } else {
                OBrowserSecret.clear ("token", "crash");
            }
        }
        OBrowserUtils.write_key_file (path, key_file);
        if (emit_signal) {
            changed (values);
        }
    }

    private string get_string (KeyFile key_file, string group, string key, string fallback) {
        try {
            return key_file.get_string (group, key);
        } catch (Error error) {
            return fallback;
        }
    }

    private bool get_bool (KeyFile key_file, string group, string key, bool fallback) {
        try {
            return key_file.get_boolean (group, key);
        } catch (Error error) {
            return fallback;
        }
    }

    private double get_double (KeyFile key_file, string group, string key, double fallback) {
        try {
            return key_file.get_double (group, key);
        } catch (Error error) {
            return fallback;
        }
    }
}
