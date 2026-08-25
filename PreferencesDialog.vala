using Gtk;

public class PreferencesDialog : Dialog {
    private SecurityManager security_manager;
    private Entry home_entry;
    private ComboBoxText startup_combo;
    private ComboBoxText engine_combo;
    private FileChooserButton download_button;
    private CheckButton ask_save_button;
    private SpinButton zoom_spin;
    private CheckButton status_bar_button;
    private CheckButton bookmarks_bar_button;
    private ComboBoxText ui_theme_combo;
    private CheckButton save_history_button;
    private CheckButton restore_session_button;
    private CheckButton javascript_button;
    private CheckButton images_button;
    private CheckButton devtools_button;
    private Entry user_agent_entry;
    private Entry update_manifest_entry;
    private ComboBoxText update_channel_combo;
    private Entry update_pubkey_entry;
    private Entry update_next_pubkey_entry;
    private CheckButton update_rotation_button;
    private Entry sync_endpoint_entry;
    private Entry sync_token_entry;
    private Entry crash_endpoint_entry;
    private Entry crash_token_entry;
    private Entry blacklist_search_entry;
    private ListBox blacklist_list;
    private Entry blacklist_add_entry;
    private string[] blocklist_entries = {};
    private Entry whitelist_search_entry;
    private ListBox whitelist_list;
    private Entry whitelist_add_entry;
    private ComboBoxText whitelist_scope_combo;
    private string[] whitelist_entries = {};
    private Entry test_url_entry;
    private Entry test_source_entry;
    private Label test_result_label;

    public PreferencesDialog (Gtk.Window parent, BrowserSettings settings, SearchEngineManager search_engines, SecurityManager security_manager) {
        Object (title: "Preferences", transient_for: parent, modal: true);
        add_button ("_Cancel", ResponseType.CANCEL);
        add_button ("_Save", ResponseType.ACCEPT);
        default_width = 520;
        default_height = 480;

        Gtk.Widget content = get_content_area ();
        ((Box) content).spacing = 10;
        ((Box) content).margin = 12;

        this.security_manager = security_manager;
        blocklist_entries = security_manager.list_blocklist_entries ();
        whitelist_entries = security_manager.list_whitelist_entries ();

        var notebook = new Notebook ();
        ((Box) content).pack_start (notebook, true, true, 0);

        notebook.append_page (build_general_page (settings, search_engines), new Label ("General"));
        notebook.append_page (build_downloads_page (settings), new Label ("Downloads"));
        notebook.append_page (build_appearance_page (settings), new Label ("Appearance"));
        notebook.append_page (build_privacy_page (settings), new Label ("Privacy"));
        notebook.append_page (build_content_page (settings), new Label ("Content"));
        notebook.append_page (build_integrations_page (settings), new Label ("Integrations"));
        notebook.append_page (build_security_page (), new Label ("Security"));

        show_all ();
    }

    public BrowserSettings read_settings () {
        var settings = new BrowserSettings ();
        settings.home_page = home_entry.text;
        settings.search_engine_id = engine_combo.get_active_id () ?? "google";
        settings.startup_behavior = StartupBehavior.from_key (startup_combo.get_active_id () ?? "home");
        settings.restore_session = restore_session_button.active;
        settings.download_directory = download_button.get_filename () ?? "";
        settings.ask_download_location = ask_save_button.active;
        settings.default_zoom_level = zoom_spin.get_value ();
        settings.show_status_bar = status_bar_button.active;
        settings.show_bookmarks_bar = bookmarks_bar_button.active;
        settings.ui_theme = ui_theme_combo.get_active_id () ?? "light";
        settings.save_history = save_history_button.active;
        settings.enable_javascript = javascript_button.active;
        settings.enable_images = images_button.active;
        settings.enable_developer_tools = devtools_button.active;
        settings.user_agent = user_agent_entry.text;
        settings.update_manifest_url = update_manifest_entry.text;
        settings.update_channel = update_channel_combo.get_active_id () ?? "stable";
        settings.update_pinned_pubkey = update_pubkey_entry.text;
        settings.update_next_pubkey = update_next_pubkey_entry.text;
        settings.update_allow_key_rotation = update_rotation_button.active;
        settings.sync_endpoint = sync_endpoint_entry.text;
        settings.sync_token = sync_token_entry.text;
        settings.crash_endpoint = crash_endpoint_entry.text;
        settings.crash_token = crash_token_entry.text;
        return settings;
    }

    private Widget build_general_page (BrowserSettings settings, SearchEngineManager search_engines) {
        var grid = create_grid ();
        home_entry = new Entry ();
        home_entry.text = settings.home_page;

        startup_combo = new ComboBoxText ();
        startup_combo.append ("home", "Open home page");
        startup_combo.append ("restore", "Restore previous session");
        startup_combo.append ("blank", "Open blank page");
        startup_combo.set_active_id (settings.startup_behavior.to_key ());

        engine_combo = new ComboBoxText ();
        foreach (SearchEngine engine in search_engines.list_engines ()) {
            engine_combo.append (engine.id, engine.name);
        }
        engine_combo.set_active_id (settings.search_engine_id);

        attach_row (grid, 0, "Home page", home_entry);
        attach_row (grid, 1, "Startup behavior", startup_combo);
        attach_row (grid, 2, "Default search", engine_combo);
        return grid;
    }

    private Widget build_downloads_page (BrowserSettings settings) {
        var box = new Box (Orientation.VERTICAL, 8);
        download_button = new FileChooserButton ("Download Directory", FileChooserAction.SELECT_FOLDER);
        if (settings.download_directory.strip () != "") {
            download_button.set_filename (settings.download_directory);
        }
        ask_save_button = new CheckButton.with_label ("Ask where to save each file");
        ask_save_button.active = settings.ask_download_location;
        box.pack_start (download_button, false, false, 0);
        box.pack_start (ask_save_button, false, false, 0);
        return box;
    }

    private Widget build_appearance_page (BrowserSettings settings) {
        var box = new Box (Orientation.VERTICAL, 8);
        var adjustment = new Adjustment (settings.default_zoom_level, 0.3, 5.0, 0.1, 0.1, 0.0);
        zoom_spin = new SpinButton (adjustment, 0.1, 2);
        ui_theme_combo = new ComboBoxText ();
        ui_theme_combo.append ("light", "Light");
        ui_theme_combo.append ("dark", "Dark");
        ui_theme_combo.append ("firefox", "Firefox");
        ui_theme_combo.append ("holographic", "Holographic");
        ui_theme_combo.set_active_id (settings.ui_theme);
        status_bar_button = new CheckButton.with_label ("Show status bar");
        status_bar_button.active = settings.show_status_bar;
        bookmarks_bar_button = new CheckButton.with_label ("Show bookmarks bar");
        bookmarks_bar_button.active = settings.show_bookmarks_bar;
        box.pack_start (new Label ("Default zoom level"), false, false, 0);
        box.pack_start (zoom_spin, false, false, 0);
        box.pack_start (new Label ("UI theme"), false, false, 0);
        box.pack_start (ui_theme_combo, false, false, 0);
        box.pack_start (status_bar_button, false, false, 0);
        box.pack_start (bookmarks_bar_button, false, false, 0);
        return box;
    }

    private Widget build_privacy_page (BrowserSettings settings) {
        var box = new Box (Orientation.VERTICAL, 8);
        save_history_button = new CheckButton.with_label ("Save browsing history");
        save_history_button.active = settings.save_history;
        restore_session_button = new CheckButton.with_label ("Allow session restore");
        restore_session_button.active = settings.restore_session;
        box.pack_start (save_history_button, false, false, 0);
        box.pack_start (restore_session_button, false, false, 0);
        return box;
    }

    private Widget build_content_page (BrowserSettings settings) {
        var box = new Box (Orientation.VERTICAL, 8);
        javascript_button = new CheckButton.with_label ("Enable JavaScript");
        javascript_button.active = settings.enable_javascript;
        images_button = new CheckButton.with_label ("Load images automatically");
        images_button.active = settings.enable_images;
        devtools_button = new CheckButton.with_label ("Enable developer tools");
        devtools_button.active = settings.enable_developer_tools;
        user_agent_entry = new Entry ();
        user_agent_entry.placeholder_text = "Optional custom user agent";
        user_agent_entry.text = settings.user_agent;
        box.pack_start (javascript_button, false, false, 0);
        box.pack_start (images_button, false, false, 0);
        box.pack_start (devtools_button, false, false, 0);
        box.pack_start (new Label ("User agent"), false, false, 0);
        box.pack_start (user_agent_entry, false, false, 0);
        return box;
    }

    private Widget build_integrations_page (BrowserSettings settings) {
        var grid = create_grid ();
        update_manifest_entry = new Entry ();
        update_manifest_entry.text = settings.update_manifest_url;
        update_channel_combo = new ComboBoxText ();
        update_channel_combo.append ("stable", "stable");
        update_channel_combo.append ("beta", "beta");
        update_channel_combo.append ("dev", "dev");
        update_channel_combo.set_active_id (settings.update_channel);
        update_pubkey_entry = new Entry ();
        update_pubkey_entry.text = settings.update_pinned_pubkey;
        update_pubkey_entry.placeholder_text = "/path/to/pinned_pubkey.pem";
        update_next_pubkey_entry = new Entry ();
        update_next_pubkey_entry.text = settings.update_next_pubkey;
        update_next_pubkey_entry.placeholder_text = "/path/to/next_pubkey.pem";
        update_rotation_button = new CheckButton.with_label ("Allow key rotation (if current signature valid)");
        update_rotation_button.active = settings.update_allow_key_rotation;
        sync_endpoint_entry = new Entry ();
        sync_endpoint_entry.text = settings.sync_endpoint;
        sync_token_entry = new Entry ();
        sync_token_entry.text = settings.sync_token;
        sync_token_entry.visibility = false;
        crash_endpoint_entry = new Entry ();
        crash_endpoint_entry.text = settings.crash_endpoint;
        crash_token_entry = new Entry ();
        crash_token_entry.text = settings.crash_token;
        crash_token_entry.visibility = false;

        attach_row (grid, 0, "Update manifest URL", update_manifest_entry);
        attach_row (grid, 1, "Update channel", update_channel_combo);
        attach_row (grid, 2, "Pinned Ed25519 pubkey", update_pubkey_entry);
        attach_row (grid, 3, "Next pubkey (rotation)", update_next_pubkey_entry);
        attach_row (grid, 4, "", update_rotation_button);
        attach_row (grid, 5, "Sync endpoint", sync_endpoint_entry);
        attach_row (grid, 6, "Sync token", sync_token_entry);
        attach_row (grid, 7, "Crash endpoint", crash_endpoint_entry);
        attach_row (grid, 8, "Crash token", crash_token_entry);
        return grid;
    }

    private Widget build_security_page () {
        var box = new Box (Orientation.VERTICAL, 8);
        var help = new Label ("Domain blocklist/whitelist for Nim security guard");
        help.halign = Align.START;
        box.pack_start (help, false, false, 0);

        var blocklist_title = new Label ("Blocked domains");
        blocklist_title.halign = Align.START;
        box.pack_start (blocklist_title, false, false, 0);
        blacklist_search_entry = new Entry ();
        blacklist_search_entry.placeholder_text = "Search blocked domains";
        box.pack_start (blacklist_search_entry, false, false, 0);

        blacklist_list = new ListBox ();
        blacklist_list.selection_mode = SelectionMode.SINGLE;
        var scrolled = new ScrolledWindow (null, null);
        scrolled.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        scrolled.min_content_height = 190;
        scrolled.add (blacklist_list);
        box.pack_start (scrolled, true, true, 0);

        var add_row = new Box (Orientation.HORIZONTAL, 6);
        blacklist_add_entry = new Entry ();
        blacklist_add_entry.placeholder_text = "example.com";
        var add_button = new Button.with_label ("Add");
        add_row.pack_start (blacklist_add_entry, true, true, 0);
        add_row.pack_start (add_button, false, false, 0);
        box.pack_start (add_row, false, false, 0);

        var action_row = new Box (Orientation.HORIZONTAL, 6);
        var remove_button = new Button.with_label ("Remove Selected");
        action_row.pack_start (remove_button, false, false, 0);
        box.pack_start (action_row, false, false, 0);

        var whitelist_title = new Label ("Trusted domains (security exceptions)");
        whitelist_title.halign = Align.START;
        box.pack_start (whitelist_title, false, false, 0);

        whitelist_search_entry = new Entry ();
        whitelist_search_entry.placeholder_text = "Search trusted domains";
        box.pack_start (whitelist_search_entry, false, false, 0);

        whitelist_list = new ListBox ();
        whitelist_list.selection_mode = SelectionMode.SINGLE;
        var white_scrolled = new ScrolledWindow (null, null);
        white_scrolled.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        white_scrolled.min_content_height = 120;
        white_scrolled.add (whitelist_list);
        box.pack_start (white_scrolled, true, true, 0);

        var white_add_row = new Box (Orientation.HORIZONTAL, 6);
        whitelist_add_entry = new Entry ();
        whitelist_add_entry.placeholder_text = "trusted.example.com";
        whitelist_scope_combo = new ComboBoxText ();
        whitelist_scope_combo.append ("all", "all rules");
        whitelist_scope_combo.append ("mixed-content", "mixed-content only");
        whitelist_scope_combo.append ("phishing", "phishing only");
        whitelist_scope_combo.append ("blocklist", "blocklist only");
        whitelist_scope_combo.set_active_id ("all");
        var white_add_button = new Button.with_label ("Add Trusted");
        white_add_row.pack_start (whitelist_add_entry, true, true, 0);
        white_add_row.pack_start (whitelist_scope_combo, false, false, 0);
        white_add_row.pack_start (white_add_button, false, false, 0);
        box.pack_start (white_add_row, false, false, 0);

        var white_action_row = new Box (Orientation.HORIZONTAL, 6);
        var white_remove_button = new Button.with_label ("Remove Trusted");
        white_action_row.pack_start (white_remove_button, false, false, 0);
        box.pack_start (white_action_row, false, false, 0);

        var test_title = new Label ("Test security policy");
        test_title.halign = Align.START;
        box.pack_start (test_title, false, false, 0);

        test_url_entry = new Entry ();
        test_url_entry.placeholder_text = "URL to test (e.g. http://cdn.example.com/app.js)";
        box.pack_start (test_url_entry, false, false, 0);
        test_source_entry = new Entry ();
        test_source_entry.placeholder_text = "Source URL (optional, for mixed-content checks)";
        box.pack_start (test_source_entry, false, false, 0);
        var test_button = new Button.with_label ("Test URL");
        box.pack_start (test_button, false, false, 0);
        test_result_label = new Label ("");
        test_result_label.halign = Align.START;
        box.pack_start (test_result_label, false, false, 0);

        var io_row = new Box (Orientation.HORIZONTAL, 6);
        var export_button = new Button.with_label ("Export JSON");
        var import_button = new Button.with_label ("Import JSON");
        io_row.pack_start (export_button, false, false, 0);
        io_row.pack_start (import_button, false, false, 0);
        box.pack_start (io_row, false, false, 0);

        blacklist_search_entry.changed.connect (() => { refresh_blacklist_view (); });
        add_button.clicked.connect (() => { add_blocklist_entry_from_input (); });
        blacklist_add_entry.activate.connect (() => { add_blocklist_entry_from_input (); });
        remove_button.clicked.connect (() => { remove_selected_blocklist_entry (); });
        whitelist_search_entry.changed.connect (() => { refresh_whitelist_view (); });
        white_add_button.clicked.connect (() => { add_whitelist_entry_from_input (); });
        whitelist_add_entry.activate.connect (() => { add_whitelist_entry_from_input (); });
        white_remove_button.clicked.connect (() => { remove_selected_whitelist_entry (); });
        test_button.clicked.connect (() => { run_policy_test (); });
        test_url_entry.activate.connect (() => { run_policy_test (); });
        export_button.clicked.connect (() => { export_rules_json (); });
        import_button.clicked.connect (() => { import_rules_json (); });

        refresh_blacklist_view ();
        refresh_whitelist_view ();
        return box;
    }

    public string[] read_blocklist_entries () {
        return blocklist_entries;
    }

    public string[] read_whitelist_entries () {
        return whitelist_entries;
    }

    private void add_blocklist_entry_from_input () {
        string entry = blacklist_add_entry.text.strip ().down ();
        if (entry == "" || entry.contains (" ")) {
            return;
        }
        foreach (string existing in blocklist_entries) {
            if (existing == entry) {
                blacklist_add_entry.text = "";
                return;
            }
        }
        blocklist_entries += entry;
        blacklist_add_entry.text = "";
        refresh_blacklist_view ();
    }

    private void remove_selected_blocklist_entry () {
        ListBoxRow? row = blacklist_list.get_selected_row ();
        if (row == null) {
            return;
        }
        Label? label = row.get_child () as Label;
        if (label == null) {
            return;
        }
        string value = label.label;
        string[] updated = {};
        foreach (string existing in blocklist_entries) {
            if (existing != value) {
                updated += existing;
            }
        }
        blocklist_entries = updated;
        refresh_blacklist_view ();
    }

    private void refresh_blacklist_view () {
        string filter = blacklist_search_entry != null ? blacklist_search_entry.text.strip ().down () : "";
        foreach (Widget child in blacklist_list.get_children ()) {
            blacklist_list.remove (child);
        }
        foreach (string entry in blocklist_entries) {
            if (filter != "" && !entry.contains (filter)) {
                continue;
            }
            var label = new Label (entry);
            label.halign = Align.START;
            blacklist_list.add (label);
        }
        blacklist_list.show_all ();
    }

    private void add_whitelist_entry_from_input () {
        string entry = whitelist_add_entry.text.strip ().down ();
        string scope = whitelist_scope_combo.get_active_id () ?? "all";
        if (entry == "" || entry.contains (" ")) {
            return;
        }
        string composed = scope == "all" ? entry : "%s|%s".printf (entry, scope);
        foreach (string existing in whitelist_entries) {
            if (existing == composed) {
                whitelist_add_entry.text = "";
                return;
            }
        }
        whitelist_entries += composed;
        whitelist_add_entry.text = "";
        refresh_whitelist_view ();
    }

    private void remove_selected_whitelist_entry () {
        ListBoxRow? row = whitelist_list.get_selected_row ();
        if (row == null) {
            return;
        }
        Label? label = row.get_child () as Label;
        if (label == null) {
            return;
        }
        string value = label.label;
        int marker = value.last_index_of (" [");
        if (marker > 0 && value.has_suffix ("]")) {
            value = value.substring (0, marker);
        }
        string[] updated = {};
        foreach (string existing in whitelist_entries) {
            if (existing != value) {
                updated += existing;
            }
        }
        whitelist_entries = updated;
        refresh_whitelist_view ();
    }

    private void refresh_whitelist_view () {
        string filter = whitelist_search_entry != null ? whitelist_search_entry.text.strip ().down () : "";
        foreach (Widget child in whitelist_list.get_children ()) {
            whitelist_list.remove (child);
        }
        foreach (string entry in whitelist_entries) {
            string shown = entry;
            if (entry.contains ("|")) {
                string[] parts = entry.split ("|");
                if (parts.length == 2) {
                    shown = "%s [%s]".printf (parts[0], parts[1]);
                }
            }
            if (filter != "" && !shown.down ().contains (filter)) {
                continue;
            }
            var label = new Label (shown);
            label.halign = Align.START;
            whitelist_list.add (label);
        }
        whitelist_list.show_all ();
    }

    private void run_policy_test () {
        string target = test_url_entry.text.strip ();
        string source = test_source_entry.text.strip ();
        if (target == "") {
            test_result_label.label = "Enter URL to test.";
            return;
        }

        security_manager.replace_blocklist_entries (blocklist_entries);
        security_manager.replace_whitelist_entries (whitelist_entries);
        string reason = "";
        bool blocked = security_manager.test_uri (target, source, out reason);
        test_result_label.label = blocked ? "BLOCKED: " + reason : "ALLOWED";
    }

    private void export_rules_json () {
        var chooser = new FileChooserDialog ("Export Security Rules", this, FileChooserAction.SAVE,
            "_Cancel", ResponseType.CANCEL, "_Save", ResponseType.ACCEPT);
        chooser.set_current_name ("security_rules.json");
        if (chooser.run () == (int) ResponseType.ACCEPT) {
            string? path = chooser.get_filename ();
            if (path != null) {
                security_manager.replace_blocklist_entries (blocklist_entries);
                security_manager.replace_whitelist_entries (whitelist_entries);
                test_result_label.label = security_manager.export_rules_json (path) ? "Exported JSON." : "Export failed.";
            }
        }
        chooser.destroy ();
    }

    private void import_rules_json () {
        var chooser = new FileChooserDialog ("Import Security Rules", this, FileChooserAction.OPEN,
            "_Cancel", ResponseType.CANCEL, "_Open", ResponseType.ACCEPT);
        if (chooser.run () == (int) ResponseType.ACCEPT) {
            string? path = chooser.get_filename ();
            if (path != null) {
                if (security_manager.import_rules_json (path)) {
                    blocklist_entries = security_manager.list_blocklist_entries ();
                    whitelist_entries = security_manager.list_whitelist_entries ();
                    refresh_blacklist_view ();
                    refresh_whitelist_view ();
                    test_result_label.label = "Imported JSON.";
                } else {
                    test_result_label.label = "Import failed.";
                }
            }
        }
        chooser.destroy ();
    }

    private Grid create_grid () {
        var grid = new Grid ();
        grid.row_spacing = 8;
        grid.column_spacing = 8;
        return grid;
    }

    private void attach_row (Grid grid, int row, string label_text, Widget widget) {
        var label = new Label (label_text);
        label.halign = Align.START;
        grid.attach (label, 0, row, 1, 1);
        grid.attach (widget, 1, row, 1, 1);
    }
}
