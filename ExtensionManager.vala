using GLib;
using WebKit;

public class ExtensionEntry : Object {
    public string id { get; set; }
    public string name { get; set; }
    public bool enabled { get; set; }
    public string script_file { get; set; }
    public string style_file { get; set; }
    public string store_id { get; set; }
    public string version { get; set; }
    public string category { get; set; }
    public string manifest { get; set; }
    public string package_hash { get; set; }

    public ExtensionEntry (string id, string name, bool enabled, string script_file, string style_file, string store_id = "", string version = "", string category = "", string manifest = "", string package_hash = "") {
        this.id = id;
        this.name = name;
        this.enabled = enabled;
        this.script_file = script_file;
        this.style_file = style_file;
        this.store_id = store_id;
        this.version = version;
        this.category = category;
        this.manifest = manifest;
        this.package_hash = package_hash;
    }
}

public class ExtensionManager : Object {
    private string extensions_dir;
    private string index_path;

    public ExtensionManager (AppPaths paths) {
        extensions_dir = Path.build_filename (paths.data_dir, "extensions");
        index_path = Path.build_filename (extensions_dir, "extensions.ini");
        OBrowserUtils.ensure_directory (extensions_dir);
        OBrowserUtils.ensure_file_exists (index_path);
    }

    public ExtensionEntry[] list_extensions () {
        var key_file = OBrowserUtils.load_key_file_safe (index_path);
        ExtensionEntry[] entries = {};
        foreach (string group in key_file.get_groups ()) {
            string id = group;
            string name = get_string (key_file, group, "name", id);
            bool enabled = get_bool (key_file, group, "enabled", true);
            string script_file = get_string (key_file, group, "script", "");
            string style_file = get_string (key_file, group, "style", "");
            string store_id = get_string (key_file, group, "store_id", "");
            string version = get_string (key_file, group, "version", "");
            string category = get_string (key_file, group, "category", "");
            string manifest = get_string (key_file, group, "manifest", "");
            string package_hash = get_string (key_file, group, "package_hash", "");
            entries += new ExtensionEntry (id, name, enabled, script_file, style_file, store_id, version, category, manifest, package_hash);
        }
        return entries;
    }

    public bool install_from_files (string name, string script_source, string style_source) {
        return install_from_source (name, script_source, style_source, "", "", "", "", "");
    }

    public bool install_from_store (string store_id, string name, string script_source, string style_source, string version, string category, string manifest, string package_hash) {
        return install_from_source (name, script_source, style_source, store_id, version, category, manifest, package_hash);
    }

    public ExtensionEntry? find_by_store_id (string store_id) {
        foreach (ExtensionEntry entry in list_extensions ()) {
            if (entry.store_id == store_id) {
                return entry;
            }
        }
        return null;
    }

    private bool install_from_source (string name, string script_source, string style_source, string store_id, string version, string category, string manifest, string package_hash) {
        string clean_name = name.strip () != "" ? name.strip () : "Extension";
        string id = "ext-" + clean_name.down ().replace (" ", "-").replace ("/", "-") + "-" + OBrowserUtils.now_unix ().to_string ();
        ExtensionEntry? existing = store_id.strip () != "" ? find_by_store_id (store_id) : null;
        if (existing != null) {
            id = existing.id;
        }
        string target_dir = Path.build_filename (extensions_dir, id);
        OBrowserUtils.ensure_directory (target_dir);

        string script_rel = "";
        string style_rel = "";

        if (script_source.strip () != "" && FileUtils.test (script_source, FileTest.EXISTS)) {
            if (!is_safe_package_path (script_source)) {
                warning ("Blocked extension install: script path escapes package directory: %s", script_source);
                return false;
            }
            string target_script = Path.build_filename (target_dir, "userscript.js");
            if (!copy_file (script_source, target_script)) {
                return false;
            }
            script_rel = Path.build_filename (id, "userscript.js");
        }

        if (style_source.strip () != "" && FileUtils.test (style_source, FileTest.EXISTS)) {
            if (!is_safe_package_path (style_source)) {
                warning ("Blocked extension install: style path escapes package directory: %s", style_source);
                return false;
            }
            string target_style = Path.build_filename (target_dir, "userstyle.css");
            if (!copy_file (style_source, target_style)) {
                return false;
            }
            style_rel = Path.build_filename (id, "userstyle.css");
        }

        upsert_entry (new ExtensionEntry (id, clean_name, true, script_rel, style_rel, store_id, version, category, manifest, package_hash));
        return true;
    }

    private bool is_safe_package_path (string source_path) {
        string? packages_dir = OBrowserUtils.find_tool ("tools/webstore_packages");
        packages_dir = packages_dir != null ? Path.get_dirname (packages_dir) : null;
        if (packages_dir == null) {
            return false;
        }
        string? canonical_packages = realpath_canonical (packages_dir);
        string? canonical_source = realpath_canonical (source_path);
        if (canonical_packages == null || canonical_source == null) {
            return false;
        }
        return canonical_source.has_prefix (canonical_packages);
    }

    private string? realpath_canonical (string path) {
        string resolved = Path.build_filename (path);
        try {
            var file = File.new_for_path (resolved);
            var info = file.query_info ("standard::symlink-target", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
            string? target = info.get_symlink_target ();
            if (target != null && target.strip () != "") {
                string target_resolved = Path.is_absolute (target) ? target : Path.build_filename (Path.get_dirname (resolved), target);
                return realpath_canonical (target_resolved);
            }
        } catch (Error error) {
        }
        return resolved;
    }

    public void set_enabled (string id, bool enabled) {
        ExtensionEntry[] entries = list_extensions ();
        for (int i = 0; i < entries.length; i++) {
            if (entries[i].id == id) {
                entries[i].enabled = enabled;
                break;
            }
        }
        save_all (entries);
    }

    public void remove (string id) {
        ExtensionEntry[] filtered = {};
        foreach (ExtensionEntry entry in list_extensions ()) {
            if (entry.id != id) {
                filtered += entry;
            }
        }
        save_all (filtered);
        string dir = Path.build_filename (extensions_dir, id);
        if (FileUtils.test (dir, FileTest.IS_DIR)) {
            try {
                Process.spawn_command_line_sync ("rm -rf " + Shell.quote (dir), null, null, null);
            } catch (Error error) {
            }
        }
    }

    public void apply_to_view (WebView view) {
        UserContentManager manager = view.get_user_content_manager ();
        if (manager == null) {
            return;
        }

        foreach (ExtensionEntry entry in list_extensions ()) {
            if (!entry.enabled) {
                continue;
            }

            if (entry.style_file.strip () != "") {
                string style_path = Path.build_filename (extensions_dir, entry.style_file);
                if (FileUtils.test (style_path, FileTest.EXISTS)) {
                    try {
                        string css;
                        FileUtils.get_contents (style_path, out css);
                        var sheet = new UserStyleSheet (css, UserContentInjectedFrames.ALL_FRAMES, UserStyleLevel.USER, null, null);
                        manager.add_style_sheet (sheet);
                    } catch (Error error) {
                    }
                }
            }

            if (entry.script_file.strip () != "") {
                string script_path = Path.build_filename (extensions_dir, entry.script_file);
                if (FileUtils.test (script_path, FileTest.EXISTS)) {
                    try {
                        string js;
                        FileUtils.get_contents (script_path, out js);
                        var script = new UserScript (js, UserContentInjectedFrames.ALL_FRAMES, UserScriptInjectionTime.START, null, null);
                        manager.add_script (script);
                    } catch (Error error) {
                    }
                }
            }
        }
    }

    private void upsert_entry (ExtensionEntry incoming) {
        ExtensionEntry[] entries = list_extensions ();
        bool found = false;
        for (int i = 0; i < entries.length; i++) {
            if (entries[i].id == incoming.id) {
                entries[i] = incoming;
                found = true;
                break;
            }
        }
        if (!found) {
            entries += incoming;
        }
        save_all (entries);
    }

    private void save_all (ExtensionEntry[] entries) {
        var key_file = new KeyFile ();
        foreach (ExtensionEntry entry in entries) {
            key_file.set_string (entry.id, "name", entry.name);
            key_file.set_boolean (entry.id, "enabled", entry.enabled);
            key_file.set_string (entry.id, "script", entry.script_file);
            key_file.set_string (entry.id, "style", entry.style_file);
            key_file.set_string (entry.id, "store_id", entry.store_id);
            key_file.set_string (entry.id, "version", entry.version);
            key_file.set_string (entry.id, "category", entry.category);
            key_file.set_string (entry.id, "manifest", entry.manifest);
            key_file.set_string (entry.id, "package_hash", entry.package_hash);
        }
        OBrowserUtils.write_key_file (index_path, key_file);
    }

    private bool copy_file (string source_path, string target_path) {
        try {
            string data;
            FileUtils.get_contents (source_path, out data);
            FileUtils.set_contents (target_path, data);
            return true;
        } catch (Error error) {
            return false;
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
}
