using Gtk;
using GLib;

public class WebStoreItem : Object {
    public string id { get; set; }
    public string name { get; set; }
    public string description { get; set; }
    public string category { get; set; }
    public string version { get; set; }
    public string package_hash { get; set; }
    public string manifest { get; set; }
    public string script_path { get; set; }
    public string style_path { get; set; }
}

public class WebStoreDialog : Dialog {
    public signal void install_done (bool ok, string message);

    private ExtensionManager extension_manager;
    private SecurityManager security_manager;
    private ListBox list;
    private Entry search_entry;
    private ComboBoxText category_combo;
    private string catalog_path;
    private string lua_tool_path;
    private WebStoreItem[] catalog_items = {};

    public WebStoreDialog (Gtk.Window parent, ExtensionManager extension_manager, SecurityManager security_manager) {
        Object (title: "OBrowser Web Store", transient_for: parent, modal: true);
        this.extension_manager = extension_manager;
        this.security_manager = security_manager;
        catalog_path = OBrowserUtils.find_tool ("tools/webstore_catalog.json");
        lua_tool_path = OBrowserUtils.find_tool ("tools/webstore.lua");
        add_button ("_Close", ResponseType.CLOSE);
        default_width = 760;
        default_height = 480;

        var content = (Box) get_content_area ();
        content.spacing = 8;
        content.margin = 12;

        var head = new Label ("Install userscript/userstyle extensions from Lua catalog");
        head.halign = Align.START;
        content.pack_start (head, false, false, 0);

        var controls = new Box (Orientation.HORIZONTAL, 6);
        search_entry = new Entry ();
        search_entry.placeholder_text = "Search plugins";
        category_combo = new ComboBoxText ();
        category_combo.append ("all", "All categories");
        category_combo.set_active_id ("all");
        controls.pack_start (search_entry, true, true, 0);
        controls.pack_start (category_combo, false, false, 0);
        var check_updates_button = new Button.with_label ("Check Updates");
        controls.pack_start (check_updates_button, false, false, 0);
        content.pack_start (controls, false, false, 0);

        list = new ListBox ();
        list.selection_mode = SelectionMode.NONE;
        var scroll = new ScrolledWindow (null, null);
        scroll.hexpand = true;
        scroll.vexpand = true;
        scroll.add (list);
        content.pack_start (scroll, true, true, 0);

        search_entry.changed.connect (() => { refresh (); });
        category_combo.changed.connect (() => { refresh (); });
        check_updates_button.clicked.connect (() => { run_update_check (); });
        refresh ();
        show_all ();
    }

    private void refresh () {
        foreach (Widget child in list.get_children ()) {
            list.remove (child);
        }

        catalog_items = load_catalog ();
        if (catalog_items.length == 0) {
            var row = new ListBoxRow ();
            var empty = new Label ("No catalog entries found (tools/webstore_catalog.json)");
            empty.halign = Align.START;
            row.add (empty);
            list.add (row);
            list.show_all ();
            return;
        }

        rebuild_categories ();
        string query = search_entry.text.strip ().down ();
        string category = category_combo.get_active_id () ?? "all";
        foreach (WebStoreItem item in catalog_items) {
            bool category_ok = category == "all" || item.category == category;
            bool query_ok = query == "" || item.name.down ().contains (query) || item.description.down ().contains (query) || item.id.down ().contains (query);
            if (!category_ok || !query_ok) {
                continue;
            }
            list.add (build_row (item));
        }
        list.show_all ();
    }

    private Widget build_row (WebStoreItem item) {
        var row = new ListBoxRow ();
        var box = new Box (Orientation.HORIZONTAL, 8);
        box.margin = 8;

        var left = new Box (Orientation.VERTICAL, 4);
        var name = new Label (item.name);
        name.halign = Align.START;
        name.get_style_context ().add_class ("title-4");
        var desc = new Label (item.description);
        desc.halign = Align.START;
        desc.wrap = true;
        desc.xalign = 0.0f;
        left.pack_start (name, false, false, 0);
        left.pack_start (desc, false, false, 0);

        ExtensionEntry? installed = extension_manager.find_by_store_id (item.id);
        bool has_update = installed != null && installed.version != "" && installed.version != item.version;
        string state = installed == null ? "Not installed" : (has_update ? "Update available" : "Installed");
        var meta = new Label ("%s | category: %s | version: %s".printf (state, item.category, item.version));
        meta.halign = Align.START;
        left.pack_start (meta, false, false, 0);

        var install_button = new Button.with_label (installed == null ? "Install" : (has_update ? "Update" : "Reinstall"));
        install_button.clicked.connect (() => {
            string enforce_reason = "";
            if (item.manifest.strip () != "" && security_manager.test_uri (item.manifest, "", out enforce_reason)) {
                install_done (false, "Manifest blocked by security policy: " + enforce_reason);
                return;
            }
            if (!verify_item_signature (item)) {
                install_done (false, "Signature check failed: " + item.name);
                return;
            }
            bool ok = extension_manager.install_from_store (item.id, item.name, item.script_path, item.style_path, item.version, item.category, item.manifest, item.package_hash);
            string message = ok ? "Installed: " + item.name + " " + item.version : "Install failed: " + item.name;
            install_done (ok, message);
            refresh ();
        });

        box.pack_start (left, true, true, 0);
        box.pack_start (install_button, false, false, 0);
        row.add (box);
        return row;
    }

    private WebStoreItem[] load_catalog () {
        WebStoreItem[] items = {};
        if (!FileUtils.test (lua_tool_path, FileTest.EXISTS)) {
            return items;
        }
        string cmd = "lua %s list %s".printf (Shell.quote (lua_tool_path), Shell.quote (catalog_path));
        try {
            string out_text;
            string err_text;
            int status;
            Process.spawn_command_line_sync (cmd, out out_text, out err_text, out status);
            if (status != 0) {
                return items;
            }
            foreach (string line in out_text.split ("\n")) {
                string clean = line.strip ();
                if (clean == "") {
                    continue;
                }
                string[] parts = clean.split ("\t");
                if (parts.length < 9) {
                    continue;
                }
                var item = new WebStoreItem ();
                item.id = parts[0];
                item.name = parts[1];
                item.description = parts[2];
                item.category = parts[3];
                item.version = parts[4];
                item.package_hash = parts[5];
                item.manifest = parts[6];
                item.script_path = parts[7];
                item.style_path = parts[8];
                items += item;
            }
        } catch (Error error) {
        }
        return items;
    }

    private bool verify_item_signature (WebStoreItem item) {
        string cmd = "lua %s verify %s %s".printf (Shell.quote (lua_tool_path), Shell.quote (catalog_path), Shell.quote (item.id));
        try {
            int status;
            Process.spawn_command_line_sync (cmd, null, null, out status);
            return status == 0;
        } catch (Error error) {
            return false;
        }
    }

    private void rebuild_categories () {
        string current = category_combo.get_active_id () ?? "all";
        category_combo.remove_all ();
        category_combo.append ("all", "All categories");
        HashTable<string,bool> seen = new HashTable<string,bool> (str_hash, str_equal);
        foreach (WebStoreItem item in catalog_items) {
            if (!seen.contains (item.category)) {
                seen.insert (item.category, true);
                category_combo.append (item.category, item.category);
            }
        }
        category_combo.set_active_id (current);
        if (category_combo.get_active_id () == null) {
            category_combo.set_active_id ("all");
        }
    }

    private void run_update_check () {
        string ext_ini = Path.build_filename (Environment.get_user_data_dir (), "obrowser", "extensions", "extensions.ini");
        string cmd = "lua %s check %s %s".printf (
            Shell.quote (OBrowserUtils.find_tool ("tools/webstore_update.lua")),
            Shell.quote (catalog_path),
            Shell.quote (ext_ini)
        );
        try {
            string out_text;
            string err_text;
            int status;
            Process.spawn_command_line_sync (cmd, out out_text, out err_text, out status);
            if (status == 0 && out_text.strip () != "") {
                install_done (true, "Updates available for installed plugins.");
            } else {
                install_done (true, "No plugin updates found.");
            }
        } catch (Error error) {
            install_done (false, "Update check failed.");
        }
        refresh ();
    }
}
