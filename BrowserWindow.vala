using Gtk;
using WebKit;
using GLib;
using Gdk;

private delegate void MenuCallback ();

public class BrowserWindow : ApplicationWindow {
    private SearchEngineManager search_engines;
    private SettingsManager settings_manager;
    private BookmarkManager bookmark_manager;
    private HistoryManager history_manager;
    private DownloadManager download_manager;
    private SessionManager session_manager;
    private PermissionManager permission_manager;
    private PasswordManager password_manager;
    private CrashReporter crash_reporter;
    private UpdateManager update_manager;
    private SyncManager sync_manager;
    private ExtensionManager extension_manager;
    private SecurityManager security_manager;
    private AppPaths app_paths;
    private WebContext web_context;
    private WebKit.Settings base_web_settings;
    private CssProvider theme_provider;
    private bool private_mode;

    private Box root;
    private Box top_chrome;
    private Notebook notebook;
    private Entry address_bar;
    private ComboBoxText engine_combo;
    private Button back_button;
    private Button forward_button;
    private Button reload_button;
    private Button home_button;
    private Button new_tab_button;
    private Button bookmark_button;
    private Button menu_button;
    private Button extensions_center_button;
    private Button webstore_center_button;
    private EntryCompletion omnibox_completion;
    private Gtk.ListStore omnibox_store;
    private ProgressBar progress_bar;
    private Label status_label;
    private Label private_label;
    private Box bookmarks_bar;
    private Revealer bookmarks_revealer;
    private FindBar find_bar;
    private ShortcutManager shortcut_manager;
    private DownloadDialog? download_dialog = null;
    private ExtensionDialog? extension_dialog = null;
    private WebStoreDialog? webstore_dialog = null;
    private uint omnibox_pulse_id = 0;
    private uint tab_pulse_id = 0;
    private uint session_save_timeout_id = 0;

    public BrowserWindow (Gtk.Application app, bool private_mode = false) {
        Object (application: app, title: private_mode ? "OBrowser (Private)" : "OBrowser");
        set_default_size (1440, 920);
        this.private_mode = private_mode;

        app_paths = new AppPaths ();
        security_manager = new SecurityManager (app_paths);
        search_engines = new SearchEngineManager ();
        settings_manager = new SettingsManager (app_paths);
        bookmark_manager = new BookmarkManager (app_paths);
        history_manager = new HistoryManager (app_paths);
        session_manager = new SessionManager (app_paths);
        download_manager = new DownloadManager (app_paths, settings_manager, security_manager);
        permission_manager = new PermissionManager (this);
        password_manager = new PasswordManager (app_paths);
        crash_reporter = new CrashReporter (app_paths);
        update_manager = new UpdateManager (app_paths);
        sync_manager = new SyncManager (app_paths);
        extension_manager = new ExtensionManager (app_paths);
        web_context = build_web_context (private_mode);
        base_web_settings = build_web_settings (settings_manager.snapshot ());
        crash_reporter.install ();

        // Periodically persist the session so a crash can be recovered from a
        // recent snapshot (SessionManager only writes on explicit lifecycle events).
        session_save_timeout_id = Timeout.add_seconds (30, () => {
            if (!private_mode) {
                save_session ();
            }
            return true;
        });
        crash_reporter.log_event ("BrowserWindow initialized");

        shortcut_manager = new ShortcutManager (this, app);
        theme_provider = new CssProvider ();
        download_manager.attach_to_context (web_context, private_mode, this);
        download_manager.changed.connect (() => {
            if (download_dialog != null) {
                download_dialog.refresh (download_manager.list_entries ());
            }
        });
        download_manager.status_message.connect ((message) => { status_label.label = message; });
        settings_manager.changed.connect ((settings_values) => { apply_settings (settings_values); });

        SearchEngine? selected = search_engines.by_id (settings_manager.search_engine_id);
        search_engines.set_selected_index (selected != null ? search_engines.index_of_id (selected.id) : 0);

        build_ui ();
        install_shortcuts ();
        connect_signals ();
        restore_or_open_default_tabs ();
        apply_settings (settings_manager.snapshot ());
        refresh_ui ();
        if (tab_pulse_id == 0) {
            tab_pulse_id = Timeout.add (240, () => {
                pulse_active_tab ();
                return true;
            });
        }
        show_all ();
    }

    private WebContext build_web_context (bool private_mode) {
        WebContext context = private_mode ? new WebContext.ephemeral () : new WebContext ();
        if (!private_mode) {
            context.set_favicon_database_directory (app_paths.cache_dir);
        }
        context.set_cache_model (CacheModel.DOCUMENT_VIEWER);
        return context;
    }

    private WebKit.Settings build_web_settings (BrowserSettings settings_values) {
        var settings = new WebKit.Settings ();
        settings.enable_developer_extras = settings_values.enable_developer_tools;
        settings.enable_write_console_messages_to_stdout = settings_values.enable_developer_tools;
        settings.enable_smooth_scrolling = true;
        settings.enable_back_forward_navigation_gestures = true;
        settings.enable_page_cache = true;
        settings.javascript_can_open_windows_automatically = true;
        settings.enable_javascript = settings_values.enable_javascript;
        settings.auto_load_images = settings_values.enable_images;
        if (settings_values.user_agent.strip () != "") {
            settings.user_agent = settings_values.user_agent;
        }
        return settings;
    }

    private void build_ui () {
        root = new Box (Orientation.VERTICAL, 0);
        if (private_mode) {
            root.get_style_context ().add_class ("ob-private-window");
        }
        add (root);

        top_chrome = new Box (Orientation.VERTICAL, 0);
        top_chrome.get_style_context ().add_class ("ob-top-chrome");
        if (private_mode) {
            top_chrome.get_style_context ().add_class ("ob-private-chrome");
        }
        top_chrome.pack_start (build_toolbar (), false, false, 0);
        root.pack_start (top_chrome, false, false, 0);

        bookmarks_revealer = new Revealer ();
        bookmarks_bar = new Box (Orientation.HORIZONTAL, 4);
        bookmarks_bar.margin = 6;
        bookmarks_revealer.add (bookmarks_bar);
        root.pack_start (bookmarks_revealer, false, false, 0);

        find_bar = new FindBar ();
        root.pack_start (find_bar, false, false, 0);

        notebook = new Notebook ();
        notebook.scrollable = true;
        notebook.tab_pos = PositionType.TOP;
        notebook.get_style_context ().add_class ("ob-tabs");
        root.pack_start (notebook, true, true, 0);

        progress_bar = new ProgressBar ();
        progress_bar.show_text = false;
        root.pack_start (progress_bar, false, false, 0);

        status_label = new Label ("Ready");
        status_label.halign = Align.START;
        status_label.margin = 6;
        root.pack_start (status_label, false, false, 0);
    }

    private Widget build_toolbar () {
        var box = new Box (Orientation.HORIZONTAL, 8);
        box.margin = 8;
        box.get_style_context ().add_class ("ob-toolbar");
        box.get_style_context ().add_class ("ob-firefox-toolbar");

        var app_icon_path = OBrowserUtils.find_tool ("data/icons/obrowser.svg");
        Image app_icon;
        if (FileUtils.test (app_icon_path, FileTest.EXISTS)) {
            app_icon = new Image.from_file (app_icon_path);
        } else {
            app_icon = new Image.from_icon_name ("web-browser-symbolic", IconSize.BUTTON);
        }
        var icon_wrap = new Box (Orientation.HORIZONTAL, 0);
        icon_wrap.margin_end = 4;
        icon_wrap.pack_start (app_icon, false, false, 0);
        box.pack_start (icon_wrap, false, false, 0);

        back_button = new Button.from_icon_name ("go-previous-symbolic", IconSize.BUTTON);
        forward_button = new Button.from_icon_name ("go-next-symbolic", IconSize.BUTTON);
        reload_button = new Button.from_icon_name ("view-refresh-symbolic", IconSize.BUTTON);
        home_button = new Button.from_icon_name ("go-home-symbolic", IconSize.BUTTON);
        new_tab_button = new Button.from_icon_name ("list-add-symbolic", IconSize.BUTTON);
        bookmark_button = new Button.from_icon_name ("starred-symbolic", IconSize.BUTTON);
        menu_button = new Button.from_icon_name ("open-menu-symbolic", IconSize.BUTTON);

        back_button.get_style_context ().add_class ("flat");
        forward_button.get_style_context ().add_class ("flat");
        reload_button.get_style_context ().add_class ("flat");
        home_button.get_style_context ().add_class ("flat");
        new_tab_button.get_style_context ().add_class ("flat");
        bookmark_button.get_style_context ().add_class ("flat");
        menu_button.get_style_context ().add_class ("flat");

        var nav_group = new Box (Orientation.HORIZONTAL, 2);
        nav_group.get_style_context ().add_class ("linked");
        nav_group.get_style_context ().add_class ("ob-nav-group");
        nav_group.pack_start (back_button, false, false, 0);
        nav_group.pack_start (forward_button, false, false, 0);
        nav_group.pack_start (reload_button, false, false, 0);
        nav_group.pack_start (home_button, false, false, 0);
        box.pack_start (nav_group, false, false, 0);

        private_label = new Label (private_mode ? "Private" : "");
        private_label.get_style_context ().add_class ("ob-private-chip");
        private_label.margin_end = 6;
        box.pack_start (private_label, false, false, 0);

        engine_combo = new ComboBoxText ();
        foreach (SearchEngine engine in search_engines.list_engines ()) {
            engine_combo.append (engine.id, engine.name);
        }
        engine_combo.set_active_id (settings_manager.search_engine_id);
        engine_combo.width_request = 130;
        engine_combo.get_style_context ().add_class ("ob-engine-chip");
        box.pack_start (engine_combo, false, false, 0);

        address_bar = new Entry ();
        address_bar.hexpand = true;
        address_bar.placeholder_text = "Search or enter address";
        address_bar.get_style_context ().add_class ("ob-omnibox");
        setup_omnibox_completion ();
        box.pack_start (address_bar, true, true, 0);

        var center_group = new Box (Orientation.HORIZONTAL, 4);
        center_group.get_style_context ().add_class ("ob-actions-group");
        extensions_center_button = new Button.from_icon_name ("applications-system-symbolic", IconSize.BUTTON);
        extensions_center_button.tooltip_text = "Extensions";
        webstore_center_button = new Button.from_icon_name ("software-install-symbolic", IconSize.BUTTON);
        webstore_center_button.tooltip_text = "Web Store";
        center_group.pack_start (extensions_center_button, false, false, 0);
        center_group.pack_start (webstore_center_button, false, false, 0);
        center_group.margin_start = 2;
        center_group.margin_end = 4;
        box.pack_start (center_group, false, false, 0);

        box.pack_start (new_tab_button, false, false, 0);
        box.pack_start (bookmark_button, false, false, 0);
        box.pack_start (menu_button, false, false, 0);
        return box;
    }

    private MenuBar build_menu_bar () {
        var menu_bar = new MenuBar ();
        menu_bar.append (build_menu_item ("File", build_file_menu ()));
        menu_bar.append (build_menu_item ("Edit", build_edit_menu ()));
        menu_bar.append (build_menu_item ("View", build_view_menu ()));
        menu_bar.append (build_menu_item ("History", build_history_menu ()));
        menu_bar.append (build_menu_item ("Bookmarks", build_bookmark_menu ()));
        menu_bar.append (build_menu_item ("Downloads", build_download_menu ()));
        menu_bar.append (build_menu_item ("Privacy", build_privacy_menu ()));
        return menu_bar;
    }

    private Gtk.MenuItem build_menu_item (string label, Gtk.Menu menu) {
        var item = new Gtk.MenuItem.with_label (label);
        item.set_submenu (menu);
        return item;
    }

    private Gtk.Menu build_file_menu () {
        var menu = new Gtk.Menu ();
        append_menu_action (menu, "New Tab", () => { create_tab (effective_home_page (), true); });
        append_menu_action (menu, "New Window", () => { new BrowserWindow ((Gtk.Application) application, false).present (); });
        append_menu_action (menu, "New Private Window", () => { new BrowserWindow ((Gtk.Application) application, true).present (); });
        append_menu_action (menu, "Open Location", () => { focus_address_bar (); });
        append_menu_action (menu, "Close Tab", () => { close_current_tab (); });
        append_menu_action (menu, "Quit", () => { application.quit (); });
        return menu;
    }

    private Gtk.Menu build_edit_menu () {
        var menu = new Gtk.Menu ();
        append_menu_action (menu, "Find in Page", () => { find_bar.show_for_tab (current_tab ()); });
        append_menu_action (menu, "Preferences", () => { show_preferences (); });
        return menu;
    }

    private Gtk.Menu build_view_menu () {
        var menu = new Gtk.Menu ();
        append_menu_action (menu, "Zoom In", () => { adjust_zoom (0.1); });
        append_menu_action (menu, "Zoom Out", () => { adjust_zoom (-0.1); });
        append_menu_action (menu, "Reset Zoom", () => { reset_zoom (); });
        append_menu_action (menu, "Reload", () => { reload_current_tab (); });
        append_menu_action (menu, "Stop", () => { stop_loading_or_hide_find (); });
        append_menu_action (menu, "Developer Tools", () => { toggle_developer_tools (); });
        append_menu_action (menu, "Web Store", () => { show_webstore_dialog (); });
        append_menu_action (menu, "Extensions", () => { show_extensions_dialog (); });
        return menu;
    }

    private Gtk.Menu build_history_menu () {
        var menu = new Gtk.Menu ();
        append_menu_action (menu, "Back", () => { go_back (); });
        append_menu_action (menu, "Forward", () => { go_forward (); });
        append_menu_action (menu, "Show History", () => { show_history_dialog (); });
        append_menu_action (menu, "Clear History", () => { history_manager.clear (); refresh_ui (); });
        append_menu_action (menu, "Rebuild History Index", () => {
            bool ok = history_manager.rebuild_index_now ();
            status_label.label = ok ? "History index rebuilt" : "History indexer not available (build Nim sidecar)";
        });
        return menu;
    }

    private Gtk.Menu build_bookmark_menu () {
        var menu = new Gtk.Menu ();
        append_menu_action (menu, "Add Bookmark", () => { add_current_page_bookmark (); });
        append_menu_action (menu, "Show Bookmarks", () => { show_bookmarks_dialog (); });
        return menu;
    }

    private Gtk.Menu build_download_menu () {
        var menu = new Gtk.Menu ();
        append_menu_action (menu, "Show Downloads", () => { show_downloads_dialog (); });
        return menu;
    }

    private Gtk.Menu build_privacy_menu () {
        var menu = new Gtk.Menu ();
        append_menu_action (menu, "Clear Browsing Data", () => { show_clear_data_dialog (); });
        append_menu_action (menu, "Save Password for Site", () => { save_password_for_current_site (); });
        append_menu_action (menu, "Manage Passwords", () => { show_password_entries (); });
        append_menu_action (menu, "Check Updates", () => { check_for_updates (); });
        append_menu_action (menu, "Sync Now", () => { run_sync_now (); });
        append_menu_action (menu, "Upload Crash Log", () => { upload_crash_log (); });
        append_menu_action (menu, "Security Audit Log", () => { show_security_audit_log (); });
        append_menu_action (menu, "Open Private Window", () => { new BrowserWindow ((Gtk.Application) application, true).present (); });
        return menu;
    }

    private void append_menu_action (Gtk.Menu menu, string label, owned MenuCallback action) {
        var item = new Gtk.MenuItem.with_label (label);
        item.activate.connect (() => { action (); });
        menu.append (item);
    }

    private void install_shortcuts () {
        shortcut_manager.register ("new-tab", "<Primary>t", () => { create_tab (effective_home_page (), true); });
        shortcut_manager.register ("close-tab", "<Primary>w", () => { close_current_tab (); });
        shortcut_manager.register ("focus-address", "<Primary>l", () => { focus_address_bar (); });
        shortcut_manager.register ("reload", "<Primary>r", () => { reload_current_tab (); }, "F5");
        shortcut_manager.register ("find", "<Primary>f", () => { find_bar.show_for_tab (current_tab ()); });
        shortcut_manager.register ("bookmark", "<Primary>d", () => { add_current_page_bookmark (); });
        shortcut_manager.register ("history", "<Primary>h", () => { show_history_dialog (); });
        shortcut_manager.register ("downloads", "<Primary>j", () => { show_downloads_dialog (); });
        shortcut_manager.register ("zoom-in", "<Primary>plus", () => { adjust_zoom (0.1); }, "<Primary>equal");
        shortcut_manager.register ("zoom-out", "<Primary>minus", () => { adjust_zoom (-0.1); });
        shortcut_manager.register ("zoom-reset", "<Primary>0", () => { reset_zoom (); });
        shortcut_manager.register ("private-window", "<Primary><Shift>p", () => { new BrowserWindow ((Gtk.Application) application, true).present (); });
        shortcut_manager.register ("next-tab", "<Primary>Tab", () => { switch_tab (1); });
        shortcut_manager.register ("prev-tab", "<Primary><Shift>Tab", () => { switch_tab (-1); });
        shortcut_manager.register ("back", "<Alt>Left", () => { go_back (); });
        shortcut_manager.register ("forward", "<Alt>Right", () => { go_forward (); });
        shortcut_manager.register ("escape", "Escape", () => { stop_loading_or_hide_find (); });
    }

    private void connect_signals () {
        back_button.clicked.connect (() => { go_back (); });
        forward_button.clicked.connect (() => { go_forward (); });
        reload_button.clicked.connect (() => { reload_or_stop (); });
        home_button.clicked.connect (() => { navigate_current_tab (effective_home_page ()); });
        new_tab_button.clicked.connect (() => { create_tab (effective_home_page (), true); });
        bookmark_button.clicked.connect (() => { add_current_page_bookmark (); });
        menu_button.clicked.connect (() => { show_quick_menu (); });
        extensions_center_button.clicked.connect (() => { show_extensions_dialog (); });
        webstore_center_button.clicked.connect (() => { navigate_current_tab ("obrowser://webstore"); });
        engine_combo.changed.connect (() => {
            string? id = engine_combo.get_active_id ();
            if (id != null) {
                search_engines.set_selected_index (search_engines.index_of_id (id));
            }
        });
        address_bar.activate.connect (() => { open_address_input (); });
        address_bar.changed.connect (() => { refresh_omnibox_suggestions (address_bar.text); });
        address_bar.icon_press.connect ((pos, event) => {
            if (pos == EntryIconPosition.SECONDARY) {
                reload_or_stop ();
            } else {
                show_security_audit_log ();
            }
        });
        notebook.switch_page.connect ((page, page_num) => {
            find_bar.attach_tab (current_tab ());
            refresh_ui ();
            save_session ();
        });
        size_allocate.connect ((allocation) => {
            update_density_mode (allocation.width);
        });

        delete_event.connect ((event) => {
            save_session ();
            return false;
        });

        destroy.connect (() => {
            if (session_save_timeout_id != 0) {
                Source.remove (session_save_timeout_id);
                session_save_timeout_id = 0;
            }
            if (tab_pulse_id != 0) {
                Source.remove (tab_pulse_id);
                tab_pulse_id = 0;
            }
            if (omnibox_pulse_id != 0) {
                Source.remove (omnibox_pulse_id);
                omnibox_pulse_id = 0;
            }
        });
    }

    private void show_quick_menu () {
        var menu = new Gtk.Menu ();
        append_menu_action (menu, "New Tab", () => { create_tab (effective_home_page (), true); });
        append_menu_action (menu, "History", () => { show_history_dialog (); });
        append_menu_action (menu, "Downloads", () => { show_downloads_dialog (); });
        append_menu_action (menu, "Bookmarks", () => { show_bookmarks_dialog (); });
        append_menu_action (menu, "Extensions", () => { show_extensions_dialog (); });
        append_menu_action (menu, "Web Store", () => { navigate_current_tab ("obrowser://webstore"); });
        append_menu_action (menu, "Preferences", () => { show_preferences (); });
        append_menu_action (menu, "Quit", () => { application.quit (); });
        menu.show_all ();
        menu.popup_at_widget (menu_button, Gdk.Gravity.SOUTH_EAST, Gdk.Gravity.NORTH_EAST, null);
    }

    private void apply_settings (BrowserSettings settings_values) {
        base_web_settings = build_web_settings (settings_values);
        status_label.visible = settings_values.show_status_bar;
        apply_ui_theme (settings_values.ui_theme);
        bookmarks_revealer.reveal_child = settings_values.show_bookmarks_bar;
        engine_combo.set_active_id (settings_values.search_engine_id);
        search_engines.set_selected_index (search_engines.index_of_id (settings_values.search_engine_id));
        refresh_bookmarks_bar ();
        for (int i = 0; i < notebook.get_n_pages (); i++) {
            BrowserTab? tab = notebook.get_nth_page (i) as BrowserTab;
            if (tab != null) {
                tab.apply_browser_settings (settings_values);
            }
        }
        save_session ();
        refresh_ui ();
    }

    private void apply_ui_theme (string theme_name) {
        Gtk.Settings gtk_settings = Gtk.Settings.get_default ();
        if (gtk_settings != null) {
            gtk_settings.gtk_application_prefer_dark_theme = theme_name == "dark" || theme_name == "holographic";
        }

        string css = "";
        string shared = ".ob-tabs header tab { border-radius: 10px 10px 0 0; padding: 5px 12px; margin: 0 2px; border: 1px solid transparent; transition: 180ms ease; }\n" +
                        ".ob-tabs header tab:checked { border-bottom-color: transparent; }\n" +
                        ".ob-top-chrome { padding: 4px 8px 0 8px; }\n" +
                        ".ob-tab-content { padding: 2px 6px; min-height: 24px; }\n" +
                        ".ob-tab-close { min-width: 18px; min-height: 18px; padding: 0; opacity: 0.65; }\n" +
                        ".ob-tab-close:hover { opacity: 1.0; }\n" +
                        ".ob-tab-shell { border-radius: 10px; transition: transform 170ms ease, box-shadow 170ms ease; }\n" +
                        ".ob-tab-shell:hover { transform: translateY(-1px); }\n" +
                        ".ob-tab-shell.active { box-shadow: inset 0 -2px 0 #0a84ff; }\n" +
                        ".ob-tab-shell.active.pulse-a { box-shadow: inset 0 -2px 0 #0a84ff, 0 0 0 1px rgba(10,132,255,0.16); }\n" +
                        ".ob-tab-shell.active.pulse-b { box-shadow: inset 0 -2px 0 #0a84ff, 0 0 0 1px rgba(10,132,255,0.32); }\n" +
                        ".ob-headerbar { border: none; }\n" +
                        ".ob-compact .ob-toolbar { padding: 3px; margin: 3px; }\n" +
                        ".ob-compact entry { min-height: 24px; }\n" +
                        ".ob-omnibox { font-size: 11.2pt; font-weight: 500; }\n" +
                        ".ob-omnibox:focus { box-shadow: 0 0 0 2px alpha(#0a84ff,0.35); }\n" +
                        ".ob-firefox-toolbar button { border-radius: 999px; min-width: 32px; min-height: 32px; }\n" +
                        ".ob-toolbar { min-height: 40px; }\n" +
                        ".ob-nav-group { padding: 0 3px; border-radius: 999px; }\n" +
                        ".ob-engine-chip { border-radius: 999px; padding: 2px 10px; }\n" +
                        ".ob-actions-group button { border-radius: 999px; }\n" +
                        ".ob-tabs header { padding-left: 4px; }\n" +
                        ".ob-private-chip { border-radius: 999px; padding: 2px 10px; font-weight: 700; font-size: 9.5pt; }\n" +
                        ".ob-private-window .ob-omnibox { border-color: #7a58b8; box-shadow: inset 0 0 0 1px rgba(122,88,184,0.25); }\n";
        if (theme_name == "dark") {
            css = "window { background: #101219; color: #f1f4fb; }\n" +
                  ".ob-top-chrome { background: #171a22; border-bottom: 1px solid #2a3040; }\n" +
                  ".ob-toolbar { background: #202534; border-radius: 14px; padding: 6px; border: 1px solid #2f3648; }\n" +
                  ".ob-omnibox { background: #0f131c; border-radius: 999px; border: 1px solid #3c4760; padding: 8px 16px; color: #f4f7ff; }\n" +
                  "button { border-radius: 10px; border: 1px solid #3a4152; background: #2a3040; color: #f0f4ff; }\n" +
                  "button:hover { background: #38425a; }\n" +
                  ".ob-nav-group { background: #262c3b; border: 1px solid #353e53; }\n" +
                  "menubar, menuitem { background: #1b1f28; color: #edf1f7; }\n" +
                  ".ob-tabs header tab:checked { background: #2a3141; border-color: #3a4358; }\n" +
                  ".ob-tabs header tab { background: #202736; }\n" +
                  "progressbar progress { background: #4b9cff; }\n" +
                  ".ob-private-chip { background: #3f2d63; color: #efe7ff; border: 1px solid #6d56a3; }\n" +
                  ".ob-private-chrome { box-shadow: inset 0 -2px 0 rgba(150,123,224,0.35); }";
        } else if (theme_name == "firefox") {
            css = "window { background: #f3f5fb; color: #1d2333; }\n" +
                  ".ob-top-chrome { background: linear-gradient(#fbfcff, #edf2fb); border-bottom: 1px solid #d2daea; }\n" +
                  ".ob-toolbar { background: #e8edf7; border-radius: 14px; padding: 6px; border: 1px solid #cfd9ea; }\n" +
                  ".ob-omnibox { background: #ffffff; border-radius: 999px; border: 1px solid #b7c5dc; padding: 8px 16px; }\n" +
                  ".ob-nav-group { background: #f6f9ff; border: 1px solid #ccd8ea; }\n" +
                  "button { border-radius: 10px; background: #ffffff; border: 1px solid #ccd7e8; }\n" +
                  "button:hover { background: #f1f5fd; }\n" +
                  ".ob-tabs header tab { background: #dfe7f4; }\n" +
                  ".ob-tabs header tab:hover { background: #ebf0fa; }\n" +
                  ".ob-tabs header tab:checked { background: #ffffff; border-color: #c7d2e5; }\n" +
                  "progressbar progress { background: #0a84ff; }\n" +
                  ".ob-private-chip { background: #ece2ff; color: #4f2d82; border: 1px solid #cdb5f7; }\n" +
                  ".ob-private-chrome { box-shadow: inset 0 -2px 0 rgba(125,92,197,0.35); }";
        } else if (theme_name == "holographic") {
            css = "window { background-image: linear-gradient(135deg, #081c2a, #192a56 45%, #0f3460); color: #dff8ff; }\n" +
                  ".ob-toolbar { background: rgba(8, 36, 64, 0.78); border-radius: 14px; padding: 6px; }\n" +
                  ".ob-omnibox { background: rgba(2, 18, 30, 0.82); border-radius: 18px; border: 1px solid #4ad6ff; padding: 8px 14px; }\n" +
                  "button, notebook, menubar, menuitem { background: rgba(8, 36, 64, 0.82); color: #dbfaff; border-color: #4ad6ff; }\n" +
                  "progressbar trough { background: rgba(0, 0, 0, 0.25); }\n" +
                  "progressbar progress { background: #35f2ff; }\n" +
                  ".ob-tabs header tab:checked { background: rgba(16, 72, 110, 0.92); }\n" +
                  ".ob-tabs header tab { background: rgba(10, 44, 72, 0.86); }";
        } else {
            css = "window { background: #f4f6fb; color: #1e2230; }\n" +
                  ".ob-top-chrome { background: linear-gradient(#f7f9fd, #eef2f8); border-bottom: 1px solid #d6deea; }\n" +
                  ".ob-toolbar { background: #e9eef7; border-radius: 14px; padding: 6px; border: 1px solid #d2dceb; }\n" +
                  ".ob-omnibox { background: #ffffff; border-radius: 999px; border: 1px solid #bcc9dd; padding: 8px 16px; }\n" +
                  "button { border-radius: 10px; background: #ffffff; border: 1px solid #ccd7e8; }\n" +
                  "button:hover { background: #f2f6fd; }\n" +
                  ".ob-nav-group { background: #f7faff; border: 1px solid #cfd8e8; }\n" +
                  "menubar, menuitem { background: #edf3fb; color: #202534; }\n" +
                  "notebook header { background: #e9eef6; border-bottom: 1px solid #d2dceb; }\n" +
                  "progressbar progress { background: #0a84ff; }\n" +
                  ".ob-tabs header tab:checked { background: #ffffff; border-color: #cbd6e6; }\n" +
                  ".ob-tabs header tab { background: #dde6f3; }\n" +
                  ".ob-private-chip { background: #efe6ff; color: #5a2f95; border: 1px solid #d2bdf3; }\n" +
                  ".ob-private-chrome { box-shadow: inset 0 -2px 0 rgba(125,92,197,0.28); }";
        }
        css += shared;

        try {
            theme_provider.load_from_data (css, -1);
            Gdk.Screen? screen = Gdk.Screen.get_default ();
            if (screen != null) {
                StyleContext.add_provider_for_screen (screen, theme_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            }
        } catch (Error error) {
        }
    }

    private void restore_or_open_default_tabs () {
        bool restored = false;
        BrowserSettings settings_values = settings_manager.snapshot ();
        if (!private_mode && settings_values.restore_session && settings_values.startup_behavior == StartupBehavior.RESTORE_SESSION) {
            SessionState state = session_manager.load ();
            if (state.uris.length > 0) {
                for (int i = 0; i < state.uris.length; i++) {
                    create_tab (state.uris[i], i == state.active_index);
                }
                restored = true;
            }
        }

        if (!restored) {
            string initial = settings_values.startup_behavior == StartupBehavior.BLANK_PAGE ? "about:blank" : effective_home_page ();
            create_tab (initial, true);
        }
    }

    private BrowserTab create_tab (string initial_uri, bool switch_to_new_tab) {
        var tab = new BrowserTab (web_context, build_web_settings (settings_manager.snapshot ()), security_manager, private_mode);
        extension_manager.apply_to_view (tab.webview);
        Widget tab_label = build_tab_label (tab);
        int index = notebook.append_page (tab, tab_label);
        notebook.set_tab_reorderable (tab, true);
        notebook.set_tab_detachable (tab, true);

        tab.title_changed.connect (() => { update_tab_label (tab); refresh_ui (); });
        tab.uri_changed.connect (() => { update_tab_label (tab); refresh_ui (); });
        tab.loading_changed.connect (() => { update_tab_label (tab); refresh_ui (); });
        tab.favicon_changed.connect (() => { update_tab_label (tab); });
        tab.security_blocked.connect ((uri, reason) => {
            status_label.label = "Blocked: %s (%s)".printf (reason, uri);
        });
        tab.page_loaded.connect ((uri, title) => {
            if (settings_manager.save_history) {
                history_manager.add_entry (uri, title, private_mode);
            }
            if (!private_mode) {
                try_autofill_for_tab (tab);
            }
            update_tab_label (tab);
            refresh_bookmarks_bar ();
            refresh_ui ();
            save_session ();
        });
        tab.create_tab_requested.connect ((target_uri) => {
            return create_tab (target_uri.strip () != "" ? target_uri : effective_home_page (), true);
        });
        tab.internal_uri_requested.connect ((uri) => {
            return handle_internal_uri (uri);
        });
        tab.permission_requested.connect ((request, origin) => {
            return permission_manager.handle (request, origin);
        });
        tab.webview.context_menu.connect ((context_menu, event, hit_test_result) => {
            return populate_context_menu (tab, context_menu, hit_test_result);
        });

        if (switch_to_new_tab) {
            notebook.set_current_page (index);
        }

        tab.apply_browser_settings (settings_manager.snapshot ());
        update_tab_label (tab);
        tab.load_target (resolve_target (initial_uri));
        find_bar.attach_tab (tab);
        show_all ();
        save_session ();
        return tab;
    }

    private Widget build_tab_label (BrowserTab tab) {
        var event_box = new EventBox ();
        event_box.get_style_context ().add_class ("ob-tab-shell");
        var box = new Box (Orientation.HORIZONTAL, 6);
        box.get_style_context ().add_class ("ob-tab-content");
        var spinner = new Spinner ();
        var image = new Image.from_icon_name (tab.is_private ? "view-private-symbolic" : "text-x-generic-symbolic", IconSize.MENU);
        var label = new Label (tab.is_private ? "Private Tab" : "New Tab");
        label.set_max_width_chars (24);
        label.ellipsize = Pango.EllipsizeMode.END;
        var close_button = new Button.from_icon_name ("window-close-symbolic", IconSize.MENU);
        close_button.get_style_context ().add_class ("ob-tab-close");
        close_button.relief = ReliefStyle.NONE;
        close_button.focus_on_click = false;
        close_button.no_show_all = true;
        close_button.hide ();
        close_button.clicked.connect (() => { close_tab (tab); });

        spinner.margin_start = 1;
        box.pack_start (spinner, false, false, 0);
        image.margin_start = 1;
        image.margin_end = 2;
        box.pack_start (image, false, false, 0);
        box.pack_start (label, true, true, 0);
        box.pack_start (close_button, false, false, 0);
        event_box.add (box);
        event_box.button_press_event.connect ((event) => {
            if (event.button == 2) {
                close_tab (tab);
                return true;
            }
            return false;
        });
        event_box.enter_notify_event.connect ((event) => { close_button.show (); return false; });
        event_box.leave_notify_event.connect ((event) => {
            if (notebook.get_current_page () != notebook.page_num (tab)) {
                close_button.hide ();
            }
            return false;
        });
        event_box.show_all ();
        tab.set_data<Label> ("tab-title-label", label);
        tab.set_data<Spinner> ("tab-spinner", spinner);
        tab.set_data<Image> ("tab-icon", image);
        tab.set_data<Button> ("tab-close", close_button);
        tab.set_data<EventBox> ("tab-shell", event_box);
        return event_box;
    }

    private void update_tab_label (BrowserTab tab) {
        Label? label = tab.get_data<Label> ("tab-title-label");
        Spinner? spinner = tab.get_data<Spinner> ("tab-spinner");
        Image? image = tab.get_data<Image> ("tab-icon");
        if (label != null) {
            string prefix = tab.is_private ? "[Private] " : "";
            label.label = prefix + tab.display_title ();
            label.tooltip_text = tab.current_uri ();
        }
        if (image != null) {
            if (tab.favicon != null) {
                image.set_from_pixbuf (tab.favicon);
            } else {
                image.set_from_icon_name (tab.is_private ? "view-private-symbolic" : "text-x-generic-symbolic", IconSize.MENU);
            }
        }
        if (spinner != null) {
            if (tab.webview.is_loading) {
                spinner.start ();
                spinner.show ();
            } else {
                spinner.stop ();
                spinner.hide ();
            }
        }
        update_tab_states ();
    }

    private void update_tab_states () {
        int current = notebook.get_current_page ();
        for (int i = 0; i < notebook.get_n_pages (); i++) {
            BrowserTab? tab = notebook.get_nth_page (i) as BrowserTab;
            if (tab == null) {
                continue;
            }
            EventBox? shell = tab.get_data<EventBox> ("tab-shell");
            Button? close_button = tab.get_data<Button> ("tab-close");
            if (shell != null) {
                StyleContext ctx = shell.get_style_context ();
                if (i == current) {
                    ctx.add_class ("active");
                    ctx.add_class ("pulse-a");
                    ctx.remove_class ("pulse-b");
                    if (close_button != null) {
                        close_button.show ();
                    }
                } else {
                    ctx.remove_class ("active");
                    ctx.remove_class ("pulse-a");
                    ctx.remove_class ("pulse-b");
                    if (close_button != null) {
                        close_button.hide ();
                    }
                }
            }
        }
    }

    private void pulse_active_tab () {
        int i = notebook.get_current_page ();
        BrowserTab? tab = notebook.get_nth_page (i) as BrowserTab;
        if (tab == null) {
            return;
        }
        EventBox? shell = tab.get_data<EventBox> ("tab-shell");
        if (shell == null) {
            return;
        }
        StyleContext ctx = shell.get_style_context ();
        if (ctx.has_class ("pulse-a")) {
            ctx.remove_class ("pulse-a");
            ctx.add_class ("pulse-b");
        } else {
            ctx.remove_class ("pulse-b");
            ctx.add_class ("pulse-a");
        }
    }

    private BrowserTab? current_tab () {
        Widget? page = notebook.get_nth_page (notebook.get_current_page ());
        return page as BrowserTab;
    }

    private void close_current_tab () {
        BrowserTab? tab = current_tab ();
        if (tab != null) {
            close_tab (tab);
        }
    }

    private void close_tab (BrowserTab tab) {
        int index = notebook.page_num (tab);
        if (index >= 0) {
            notebook.remove_page (index);
        }
        if (notebook.get_n_pages () == 0) {
            create_tab (effective_home_page (), true);
        }
        refresh_ui ();
        save_session ();
    }

    private void switch_tab (int delta) {
        int count = notebook.get_n_pages ();
        if (count <= 1) {
            return;
        }
        int current = notebook.get_current_page ();
        int next = (current + delta + count) % count;
        notebook.set_current_page (next);
    }

    private void go_back () {
        BrowserTab? tab = current_tab ();
        if (tab != null) {
            tab.go_back_if_possible ();
        }
    }

    private void go_forward () {
        BrowserTab? tab = current_tab ();
        if (tab != null) {
            tab.go_forward_if_possible ();
        }
    }

    private void reload_current_tab () {
        BrowserTab? tab = current_tab ();
        if (tab != null) {
            tab.reload_tab ();
        }
    }

    private void reload_or_stop () {
        BrowserTab? tab = current_tab ();
        if (tab == null) {
            return;
        }
        if (tab.webview.is_loading) {
            tab.stop_loading_tab ();
        } else if (tab.has_error ()) {
            tab.load_target (resolve_target (tab.retry_uri ()));
        } else {
            tab.reload_tab ();
        }
    }

    private void navigate_current_tab (string target) {
        BrowserTab? tab = current_tab ();
        if (tab != null) {
            string resolved = resolve_target (target);
            if (!handle_internal_uri (resolved)) {
                tab.load_target (resolved);
            }
        }
    }

    private string resolve_target (string text) {
        string resolved = search_engines.resolve_input (text);
        return resolved;
    }

    private void open_address_input () {
        string target = resolve_target (address_bar.text);
        if (!handle_internal_uri (target)) {
            navigate_current_tab (target);
        }
    }

    private Widget build_header_bar () {
        var hb = new HeaderBar ();
        hb.show_close_button = true;
        hb.title = "OBrowser";
        hb.subtitle = private_mode ? "Private" : "Secure Browser";
        hb.get_style_context ().add_class ("ob-headerbar");

        var left = new Box (Orientation.HORIZONTAL, 2);
        var mini_back = new Button.from_icon_name ("go-previous-symbolic", IconSize.MENU);
        var mini_forward = new Button.from_icon_name ("go-next-symbolic", IconSize.MENU);
        mini_back.get_style_context ().add_class ("flat");
        mini_forward.get_style_context ().add_class ("flat");
        mini_back.clicked.connect (() => { go_back (); });
        mini_forward.clicked.connect (() => { go_forward (); });
        left.pack_start (mini_back, false, false, 0);
        left.pack_start (mini_forward, false, false, 0);
        hb.pack_start (left);

        var right = new Box (Orientation.HORIZONTAL, 2);
        var mini_new_tab = new Button.from_icon_name ("list-add-symbolic", IconSize.MENU);
        mini_new_tab.get_style_context ().add_class ("flat");
        mini_new_tab.clicked.connect (() => { create_tab (effective_home_page (), true); });
        right.pack_start (mini_new_tab, false, false, 0);
        hb.pack_end (right);
        return hb;
    }

    private void setup_omnibox_completion () {
        // title, subtitle, icon-name, target-uri, source-kind
        omnibox_store = new Gtk.ListStore (5, typeof (string), typeof (string), typeof (string), typeof (string), typeof (string));
        omnibox_completion = new EntryCompletion ();
        omnibox_completion.model = omnibox_store;
        omnibox_completion.text_column = 3;
        omnibox_completion.inline_completion = false;
        omnibox_completion.popup_completion = true;
        omnibox_completion.popup_set_width = true;
        omnibox_completion.minimum_key_length = 1;

        var icon_cell = new CellRendererPixbuf ();
        var title_cell = new CellRendererText ();
        var sub_cell = new CellRendererText ();
        sub_cell.scale = 0.85;
        sub_cell.foreground = "#6b7280";
        omnibox_completion.pack_start (icon_cell, false);
        omnibox_completion.add_attribute (icon_cell, "icon-name", 2);
        omnibox_completion.pack_start (title_cell, true);
        omnibox_completion.add_attribute (title_cell, "text", 0);
        omnibox_completion.pack_start (sub_cell, true);
        omnibox_completion.add_attribute (sub_cell, "text", 1);

        omnibox_completion.set_match_func ((completion, key, iter) => {
            Value value_title;
            Value value_sub;
            omnibox_store.get_value (iter, 0, out value_title);
            omnibox_store.get_value (iter, 1, out value_sub);
            string text = "";
            string sub = "";
            try {
                text = value_title.get_string ();
                sub = value_sub.get_string ();
            } catch (Error e) {
            }
            string q = key.down ();
            return text.down ().contains (q) || sub.down ().contains (q);
        });
        omnibox_completion.match_selected.connect ((model, iter) => {
            Value v;
            model.get_value (iter, 3, out v);
            string target = "";
            try {
                target = v.get_string ();
            } catch (Error e) {
            }
            address_bar.text = target;
            open_address_input ();
            return true;
        });
        address_bar.set_completion (omnibox_completion);
    }

    private void refresh_omnibox_suggestions (string query) {
        if (omnibox_store == null) {
            return;
        }
        string q = query.strip ();
        omnibox_store.clear ();
        if (q == "") {
            return;
        }

        int added = 0;
        foreach (BookmarkEntry b in bookmark_manager.search (q)) {
            TreeIter iter;
            omnibox_store.append (out iter);
            omnibox_store.set (iter, 0, OBrowserUtils.clean_title (b.title, b.uri), 1, b.uri, 2, "starred-symbolic", 3, b.uri, 4, "bookmark");
            if (++added >= 8) break;
        }
        foreach (HistoryEntry h in history_manager.search (q)) {
            TreeIter iter;
            omnibox_store.append (out iter);
            omnibox_store.set (iter, 0, OBrowserUtils.clean_title (h.title, h.uri), 1, h.uri, 2, "document-open-recent-symbolic", 3, h.uri, 4, "history");
            if (++added >= 16) break;
        }
        TreeIter search_iter;
        omnibox_store.append (out search_iter);
        omnibox_store.set (search_iter, 0, "Search for: " + q, 1, search_engines.current ().name, 2, "edit-find-symbolic", 3, search_engines.current ().build_search_url (q), 4, "search");
    }

    private string effective_home_page () {
        return OBrowserUtils.normalize_home_page (settings_manager.home_page, "about:blank");
    }

    private void focus_address_bar () {
        address_bar.grab_focus ();
        address_bar.select_region (0, -1);
    }

    private void stop_loading_or_hide_find () {
        if (find_bar.reveal_child) {
            find_bar.hide_bar ();
            return;
        }
        BrowserTab? tab = current_tab ();
        if (tab != null && tab.webview.is_loading) {
            tab.stop_loading_tab ();
        }
    }

    private void add_current_page_bookmark () {
        BrowserTab? tab = current_tab ();
        if (tab == null) {
            return;
        }
        string uri = tab.current_uri ();
        if (uri.strip () == "" || uri.has_prefix ("obrowser://")) {
            return;
        }
        bookmark_manager.add_or_update (uri, tab.display_title ());
        status_label.label = "Bookmark saved";
        refresh_bookmarks_bar ();
        refresh_ui ();
    }

    private void refresh_bookmarks_bar () {
        foreach (Widget child in bookmarks_bar.get_children ()) {
            bookmarks_bar.remove (child);
        }
        BookmarkEntry[] entries = bookmark_manager.load_all ();
        int count = 0;
        foreach (BookmarkEntry entry in entries) {
            if (count >= 8) {
                break;
            }
            var button = new Button.with_label (entry.title);
            button.clicked.connect (() => { navigate_current_tab (entry.uri); });
            bookmarks_bar.pack_start (button, false, false, 0);
            count++;
        }
        bookmarks_revealer.reveal_child = settings_manager.show_bookmarks_bar;
        bookmarks_bar.show_all ();
    }

    private void refresh_ui () {
        BrowserTab? tab = current_tab ();
        if (tab == null) {
            return;
        }

        string uri = tab.current_uri ();
        if (!address_bar.has_focus) {
            address_bar.text = uri;
            address_bar.set_position (-1);
        }

        title = "%s%s - OBrowser".printf (private_mode ? "Private - " : "", tab.display_title ());
        status_label.label = tab.status_text ();
        update_omnibox_state (tab);
        if (tab.has_error ()) {
            progress_bar.fraction = 0.0;
            progress_bar.visible = false;
        } else {
            progress_bar.fraction = tab.webview.estimated_load_progress;
            progress_bar.visible = tab.webview.is_loading;
        }
        back_button.sensitive = tab.webview.can_go_back ();
        forward_button.sensitive = tab.webview.can_go_forward ();
        reload_button.image = new Image.from_icon_name (tab.webview.is_loading ? "process-stop-symbolic" : "view-refresh-symbolic", IconSize.BUTTON);
        bookmark_button.sensitive = uri.strip () != "" && !uri.has_prefix ("obrowser://");
        bookmark_button.image = new Image.from_icon_name (bookmark_manager.contains (uri) ? "emblem-favorite-symbolic" : "bookmark-new-symbolic", IconSize.BUTTON);
    }

    private void update_omnibox_state (BrowserTab tab) {
        string uri = tab.current_uri ();
        if (uri.has_prefix ("https://")) {
            address_bar.primary_icon_name = "changes-prevent-symbolic";
            address_bar.primary_icon_tooltip_text = "Secure connection (HTTPS)";
        } else if (uri.has_prefix ("http://")) {
            address_bar.primary_icon_name = "dialog-warning-symbolic";
            address_bar.primary_icon_tooltip_text = "Not secure (HTTP)";
        } else if (uri.has_prefix ("obrowser://")) {
            address_bar.primary_icon_name = "applications-internet-symbolic";
            address_bar.primary_icon_tooltip_text = "Internal page";
        } else {
            address_bar.primary_icon_name = "edit-find-symbolic";
            address_bar.primary_icon_tooltip_text = "Search or address";
        }

        if (tab.webview.is_loading) {
            address_bar.secondary_icon_name = "process-working-symbolic";
            start_omnibox_loading_pulse ();
        } else {
            address_bar.secondary_icon_name = "view-refresh-symbolic";
            stop_omnibox_loading_pulse ();
        }
    }

    private void start_omnibox_loading_pulse () {
        address_bar.progress_pulse_step = 0.12;
        if (omnibox_pulse_id != 0) {
            return;
        }
        omnibox_pulse_id = Timeout.add (120, () => {
            BrowserTab? tab = current_tab ();
            if (tab == null || !tab.webview.is_loading) {
                stop_omnibox_loading_pulse ();
                return false;
            }
            address_bar.progress_pulse ();
            return true;
        });
    }

    private void stop_omnibox_loading_pulse () {
        if (omnibox_pulse_id != 0) {
            Source.remove (omnibox_pulse_id);
            omnibox_pulse_id = 0;
        }
        address_bar.progress_fraction = 0.0;
    }

    private void update_density_mode (int width) {
        StyleContext context = root.get_style_context ();
        if (width < 1180) {
            context.add_class ("ob-compact");
        } else {
            context.remove_class ("ob-compact");
        }
    }

    private void save_session () {
        if (private_mode || !settings_manager.restore_session) {
            return;
        }
        string[] uris = {};
        int active = 0;
        int current_page = notebook.get_current_page ();
        for (int i = 0; i < notebook.get_n_pages (); i++) {
            BrowserTab? tab = notebook.get_nth_page (i) as BrowserTab;
            if (tab != null) {
                string uri = tab.current_uri ();
                if (OBrowserUtils.should_save_session_uri (uri)) {
                    uris += uri;
                    if (current_page == i) {
                        active = uris.length - 1;
                    }
                }
            }
        }
        if (active >= uris.length) {
            active = uris.length > 0 ? uris.length - 1 : 0;
        }
        session_manager.save (uris, active);
    }

    private void show_preferences () {
        var dialog = new PreferencesDialog (this, settings_manager.snapshot (), search_engines, security_manager);
        if (dialog.run () == (int) ResponseType.ACCEPT) {
            BrowserSettings updated = dialog.read_settings ();
            settings_manager.update (updated);
            security_manager.replace_blocklist_entries (dialog.read_blocklist_entries ());
            security_manager.replace_whitelist_entries (dialog.read_whitelist_entries ());
            status_label.label = "Security lists updated";
        }
        dialog.destroy ();
    }

    private void show_bookmarks_dialog () {
        var dialog = new BookmarkDialog (this, bookmark_manager);
        dialog.open_requested.connect ((uri, new_tab) => {
            if (new_tab) {
                create_tab (uri, true);
            } else {
                navigate_current_tab (uri);
            }
        });
        dialog.run ();
        dialog.destroy ();
        refresh_bookmarks_bar ();
        refresh_ui ();
    }

    private void show_history_dialog () {
        var dialog = new HistoryDialog (this, history_manager);
        dialog.open_requested.connect ((uri, new_tab) => {
            if (new_tab) {
                create_tab (uri, true);
            } else {
                navigate_current_tab (uri);
            }
        });
        dialog.clear_requested.connect (() => { refresh_ui (); });
        dialog.run ();
        dialog.destroy ();
    }

    private void show_downloads_dialog () {
        download_dialog = new DownloadDialog (this, download_manager.list_entries ());
        download_dialog.cancel_requested.connect ((id) => { download_manager.cancel (id); });
        download_dialog.open_requested.connect ((destination) => { download_manager.open_download (this, destination); });
        download_dialog.open_folder_requested.connect ((destination) => { download_manager.open_folder (this, destination); });
        download_dialog.clear_completed_requested.connect (() => {
            download_manager.clear_completed ();
            if (download_dialog != null) {
                download_dialog.refresh (download_manager.list_entries ());
            }
        });
        download_dialog.run ();
        download_dialog.destroy ();
        download_dialog = null;
    }

    private bool populate_context_menu (BrowserTab tab, WebKit.ContextMenu context_menu, WebKit.HitTestResult hit_test_result) {
        if (hit_test_result.context_is_link ()) {
            string link_uri = hit_test_result.get_link_uri ();
            if (link_uri.strip () != "") {
                var open_link_action = new SimpleAction ("open-link-new-tab", null);
                open_link_action.activate.connect (() => {
                    create_tab (link_uri, true);
                });
                context_menu.append (new WebKit.ContextMenuItem.from_gaction (open_link_action, "Open Link in New Tab", null));
            }
        }

        if (settings_manager.enable_developer_tools) {
            context_menu.append (new WebKit.ContextMenuItem.separator ());
            context_menu.append (new WebKit.ContextMenuItem.from_stock_action_with_label (WebKit.ContextMenuAction.INSPECT_ELEMENT, "Inspect Element"));
        }
        return false;
    }

    private void show_clear_data_dialog () {
        var dialog = new ClearDataDialog (this);
        if (dialog.run () == (int) ResponseType.ACCEPT) {
            if (dialog.clear_history ()) {
                history_manager.clear ();
            }
            if (dialog.clear_downloads ()) {
                download_manager.clear_all ();
            }
            if (dialog.clear_session ()) {
                session_manager.clear ();
            }
            if (dialog.clear_website_data ()) {
                WebsiteDataManager manager = web_context.get_website_data_manager ();
                manager.clear.begin (WebsiteDataTypes.ALL, 0, null, (obj, res) => {
                    try {
                        manager.clear.end (res);
                    } catch (Error error) {
                        status_label.label = "Failed to clear website data";
                    }
                });
                web_context.clear_cache ();
            }
            refresh_ui ();
        }
        dialog.destroy ();
    }

    private bool handle_internal_uri (string uri) {
        if (!InternalPages.is_internal_uri (uri)) {
            return false;
        }

        if (uri.has_prefix ("obrowser://about")) {
            BrowserTab? tab = current_tab ();
            if (tab != null) {
                tab.load_html_content (InternalPages.about_page (app_paths), "obrowser://about");
            }
            return true;
        }
        if (uri.has_prefix ("obrowser://settings")) {
            show_preferences ();
            return true;
        }
        if (uri.has_prefix ("obrowser://history")) {
            show_history_dialog ();
            return true;
        }
        if (uri.has_prefix ("obrowser://bookmarks")) {
            show_bookmarks_dialog ();
            return true;
        }
        if (uri.has_prefix ("obrowser://downloads")) {
            show_downloads_dialog ();
            return true;
        }
        if (uri.has_prefix ("obrowser://extensions")) {
            show_extensions_dialog ();
            return true;
        }
        if (uri == "obrowser://webstore" || uri.has_prefix ("obrowser://webstore?")) {
            BrowserTab? tab = current_tab ();
            if (tab != null) {
                tab.load_html_content (InternalPages.webstore_page (build_webstore_cards_html ()), "obrowser://webstore");
            }
            return true;
        }
        if (uri.has_prefix ("obrowser://webstore/list")) {
            show_webstore_dialog ();
            return true;
        }
        if (uri.has_prefix ("obrowser://webstore/check-updates")) {
            run_webstore_updates_check ();
            return true;
        }
        if (uri.has_prefix ("obrowser://webstore/install?id=")) {
            string id = uri.substring ("obrowser://webstore/install?id=".length);
            install_webstore_item (Uri.unescape_string (id, null));
            return true;
        }
        if (uri.has_prefix ("obrowser://retry?url=")) {
            string encoded = uri.substring ("obrowser://retry?url=".length);
            navigate_current_tab (Uri.unescape_string (encoded, null));
            return true;
        }
        return false;
    }

    private void adjust_zoom (double delta) {
        BrowserTab? tab = current_tab ();
        if (tab != null) {
            double target = tab.webview.get_zoom_level () + delta;
            if (target < 0.3) { target = 0.3; }
            if (target > 5.0) { target = 5.0; }
            tab.webview.set_zoom_level (target);
        }
    }

    private void reset_zoom () {
        BrowserTab? tab = current_tab ();
        if (tab != null) {
            tab.webview.set_zoom_level (settings_manager.default_zoom_level);
        }
    }

    private void toggle_developer_tools () {
        BrowserTab? tab = current_tab ();
        if (tab == null || !settings_manager.enable_developer_tools) {
            return;
        }
        tab.webview.get_inspector ().show ();
    }

    private void show_extensions_dialog () {
        extension_dialog = new ExtensionDialog (this, extension_manager);
        extension_dialog.changed.connect (() => {
            status_label.label = "Extension list updated. New tabs use latest extension state.";
        });
        extension_dialog.run ();
        extension_dialog.destroy ();
        extension_dialog = null;
    }

    private void show_webstore_dialog () {
        webstore_dialog = new WebStoreDialog (this, extension_manager, security_manager);
        webstore_dialog.install_done.connect ((ok, message) => {
            status_label.label = message;
            if (ok && extension_dialog != null) {
                extension_dialog.refresh_for_external_change ();
            }
        });
        webstore_dialog.run ();
        webstore_dialog.destroy ();
        webstore_dialog = null;
    }

    private void run_webstore_updates_check () {
        string script = OBrowserUtils.find_tool ("tools/webstore_update.lua");
        string catalog = OBrowserUtils.find_tool ("tools/webstore_catalog.json");
        string ext_ini = Path.build_filename (Environment.get_user_data_dir (), "obrowser", "extensions", "extensions.ini");
        if (!FileUtils.test (script, FileTest.EXISTS)) {
            status_label.label = "WebStore update tool not found";
            return;
        }
        string cmd = "lua %s check %s %s".printf (Shell.quote (script), Shell.quote (catalog), Shell.quote (ext_ini));
        try {
            string out_text;
            string err_text;
            int status;
            Process.spawn_command_line_sync (cmd, out out_text, out err_text, out status);
            if (status == 0 && out_text.strip () != "") {
                foreach (string line in out_text.split ("\n")) {
                    string clean = line.strip ();
                    if (clean == "") {
                        continue;
                    }
                    string[] p = clean.split ("\t");
                    if (p.length >= 1) {
                        install_webstore_item (p[0]);
                    }
                }
                status_label.label = "WebStore plugins updated";
            } else {
                status_label.label = "No WebStore updates";
            }
        } catch (Error error) {
            status_label.label = "WebStore updates check failed";
        }
    }

    private void install_webstore_item (string store_id) {
        string script = OBrowserUtils.find_tool ("tools/webstore.lua");
        string catalog = OBrowserUtils.find_tool ("tools/webstore_catalog.json");
        if (!FileUtils.test (script, FileTest.EXISTS)) {
            status_label.label = "WebStore tool missing";
            return;
        }
        try {
            string verify_cmd = "lua %s verify %s %s".printf (Shell.quote (script), Shell.quote (catalog), Shell.quote (store_id));
            int vstatus;
            Process.spawn_command_line_sync (verify_cmd, null, null, out vstatus);
            if (vstatus != 0) {
                status_label.label = "Install blocked: signature/hash check failed";
                return;
            }

            string list_cmd = "lua %s list %s".printf (Shell.quote (script), Shell.quote (catalog));
            string out_text;
            string err_text;
            int status;
            Process.spawn_command_line_sync (list_cmd, out out_text, out err_text, out status);
            if (status != 0) {
                status_label.label = "WebStore catalog load failed";
                return;
            }
            foreach (string line in out_text.split ("\n")) {
                string clean = line.strip ();
                if (clean == "") {
                    continue;
                }
                string[] p = clean.split ("\t");
                if (p.length < 9 || p[0] != store_id) {
                    continue;
                }
                string reason = "";
                if (p[6].strip () != "" && security_manager.test_uri (p[6], "", out reason)) {
                    status_label.label = "Install blocked by security: " + reason;
                    return;
                }
                bool ok = extension_manager.install_from_store (p[0], p[1], p[7], p[8], p[4], p[3], p[6], p[5]);
                status_label.label = ok ? "Installed from WebStore: " + p[1] : "Install failed: " + p[1];
                return;
            }
            status_label.label = "Extension not found in catalog";
        } catch (Error error) {
            status_label.label = "WebStore install failed";
        }
    }

    private void show_security_audit_log () {
        var dialog = new SecurityAuditDialog (this, security_manager.audit_tail (500));
        dialog.run ();
        dialog.destroy ();
    }

    private string build_webstore_cards_html () {
        string script = OBrowserUtils.find_tool ("tools/webstore.lua");
        string catalog = OBrowserUtils.find_tool ("tools/webstore_catalog.json");
        if (!FileUtils.test (script, FileTest.EXISTS)) {
            return "<p>WebStore tool missing.</p>";
        }
        StringBuilder html = new StringBuilder ();
        try {
            string cmd = "lua %s list %s".printf (Shell.quote (script), Shell.quote (catalog));
            string out_text;
            string err_text;
            int status;
            Process.spawn_command_line_sync (cmd, out out_text, out err_text, out status);
            if (status != 0) {
                return "<p>Failed to load catalog.</p>";
            }
            foreach (string line in out_text.split ("\n")) {
                string clean = line.strip ();
                if (clean == "") {
                    continue;
                }
                string[] p = clean.split ("\t");
                if (p.length < 9) {
                    continue;
                }
                ExtensionEntry? installed = extension_manager.find_by_store_id (p[0]);
                string state = installed == null ? "Not installed" : (installed.version != p[4] ? "Update available" : "Installed");
                string search = (p[1] + " " + p[2] + " " + p[3]).down ();
                html.append ("<div class='card' data-search='");
                html.append (Markup.escape_text (search));
                html.append ("' style='background:white;border:1px solid #d7e0ea;border-radius:12px;padding:12px'>");
                html.append ("<h3 style='margin:4px 0'>");
                html.append (Markup.escape_text (p[1]));
                html.append ("</h3><p style='font-size:13px;color:#586675'>");
                html.append (Markup.escape_text (p[2]));
                html.append ("</p><p style='font-size:12px'>");
                html.append (Markup.escape_text (p[3] + " | v" + p[4] + " | " + state));
                html.append ("</p><div style='display:flex;gap:8px'><a href='obrowser://webstore/install?id=");
                html.append (Uri.escape_string (p[0], null, true));
                html.append ("' style='padding:6px 10px;background:#1a73e8;color:white;text-decoration:none;border-radius:8px'>");
                html.append (state == "Update available" ? "Update" : "Install");
                html.append ("</a></div></div>");
            }
        } catch (Error error) {
            return "<p>Catalog parsing failed.</p>";
        }
        return html.str;
    }

    private void save_password_for_current_site () {
        BrowserTab? tab = current_tab ();
        if (tab == null) {
            return;
        }
        string origin = OBrowserUtils.origin_from_uri (tab.current_uri ());
        if (origin == "") {
            status_label.label = "Cannot determine origin";
            return;
        }

        var dialog = new Dialog.with_buttons ("Save Password", this, DialogFlags.MODAL, "_Cancel", ResponseType.CANCEL, "_Save", ResponseType.ACCEPT);
        Gtk.Widget content = dialog.get_content_area ();
        var grid = new Grid ();
        grid.margin = 10;
        grid.row_spacing = 6;
        grid.column_spacing = 6;
        var username = new Entry ();
        var password = new Entry ();
        password.visibility = false;
        grid.attach (new Label ("Origin"), 0, 0, 1, 1);
        grid.attach (new Label (origin), 1, 0, 1, 1);
        grid.attach (new Label ("Username"), 0, 1, 1, 1);
        grid.attach (username, 1, 1, 1, 1);
        grid.attach (new Label ("Password"), 0, 2, 1, 1);
        grid.attach (password, 1, 2, 1, 1);
        ((Box) content).pack_start (grid, true, true, 0);
        dialog.show_all ();
        if (dialog.run () == (int) ResponseType.ACCEPT) {
            password_manager.save_for_origin (origin, username.text, password.text);
            status_label.label = "Password saved for " + origin;
        }
        dialog.destroy ();
    }

    private void show_password_entries () {
        var dialog = new Dialog.with_buttons ("Saved Password Origins", this, DialogFlags.MODAL, "_Close", ResponseType.CLOSE);
        dialog.set_default_size (560, 320);
        Gtk.Widget content = dialog.get_content_area ();
        var list = new ListBox ();
        foreach (PasswordEntry entry in password_manager.list_all ()) {
            var row = new ListBoxRow ();
            var box = new Box (Orientation.HORIZONTAL, 6);
            box.margin = 8;
            var text = new Label ("%s (%s)".printf (entry.origin, entry.username));
            text.halign = Align.START;
            var remove = new Button.with_label ("Remove");
            string origin = entry.origin;
            remove.clicked.connect (() => {
                password_manager.remove_for_origin (origin);
                dialog.response (ResponseType.APPLY);
            });
            box.pack_start (text, true, true, 0);
            box.pack_start (remove, false, false, 0);
            row.add (box);
            list.add (row);
        }
        var scroll = new ScrolledWindow (null, null);
        scroll.add (list);
        ((Box) content).pack_start (scroll, true, true, 0);
        dialog.show_all ();
        int response = dialog.run ();
        dialog.destroy ();
        if (response == (int) ResponseType.APPLY) {
            show_password_entries ();
        }
    }

    private void try_autofill_for_tab (BrowserTab tab) {
        string origin = OBrowserUtils.origin_from_uri (tab.current_uri ());
        if (origin == "") {
            return;
        }
        PasswordEntry? entry = password_manager.find_for_origin (origin);
        if (entry == null) {
            return;
        }
        string username_js = OBrowserUtils.json_string (entry.username);
        string password_js = OBrowserUtils.json_string (entry.password);
        string js = "(function(){var u=document.querySelector('input[type=email],input[type=text],input[name*=user],input[name*=email]');var p=document.querySelector('input[type=password]');if(u){u.value=%s;}if(p){p.value=%s;}})();".printf (username_js, password_js);
        tab.webview.evaluate_javascript.begin (js, -1, null, null, null, (obj, res) => {
            try {
                tab.webview.evaluate_javascript.end (res);
            } catch (Error error) {
            }
        });
    }

    private void check_for_updates () {
        string manifest = settings_manager.update_manifest_url;
        if (manifest.strip () == "") {
            status_label.label = "Set update manifest URL in Preferences";
            return;
        }
        string channel = settings_manager.update_channel.strip () != "" ? settings_manager.update_channel : "stable";
        UpdateInfo info = update_manager.check_now (
            manifest,
            channel,
            "0.1.0",
            settings_manager.update_pinned_pubkey,
            settings_manager.update_next_pubkey,
            settings_manager.update_allow_key_rotation
        );
        if (info.update_available) {
            status_label.label = "Update available: " + info.latest_version;
        } else {
            status_label.label = "No updates";
        }
    }

    private void run_sync_now () {
        string endpoint = settings_manager.sync_endpoint;
        string token = settings_manager.sync_token;
        if (endpoint.strip () == "" || token.strip () == "") {
            status_label.label = "Set sync endpoint/token in Preferences";
            return;
        }
        bool success = sync_manager.sync_now (endpoint, token);
        status_label.label = success ? "Sync success" : "Sync failed";
    }

    private void upload_crash_log () {
        string endpoint = settings_manager.crash_endpoint;
        string token = settings_manager.crash_token;
        if (endpoint.strip () == "" || token.strip () == "") {
            status_label.label = "Set crash endpoint/token in Preferences";
            return;
        }
        crash_reporter.upload_latest_async (endpoint, token);
        status_label.label = "Crash upload started";
    }
}
