using GLib;

public class HistoryManager : Object {
    private string path;
    private string index_path;
    private string sidecar_path;
    private int max_entries = 1000;

    public HistoryManager (AppPaths app_paths) {
        path = app_paths.history_file ();
        index_path = Path.build_filename (app_paths.cache_dir, "history.index");
        sidecar_path = OBrowserUtils.find_tool ("build/history_indexer");
        OBrowserUtils.ensure_file_exists (path);
    }

    public HistoryEntry[] load_all () {
        var key_file = OBrowserUtils.load_key_file_safe (path);
        HistoryEntry[] entries = {};
        foreach (string group in key_file.get_groups ()) {
            string uri = get_string (key_file, group, "uri");
            if (uri == "") {
                continue;
            }
            entries += new HistoryEntry (
                uri,
                get_string (key_file, group, "title"),
                get_int64 (key_file, group, "visited_at"),
                get_int (key_file, group, "visit_count", 1)
            );
        }
        sort_entries (entries);
        return entries;
    }

    public HistoryEntry[] search (string query) {
        string needle = query.strip ().down ();
        if (needle == "") {
            return load_all ();
        }
        HistoryEntry[] filtered = {};
        foreach (HistoryEntry entry in load_all ()) {
            if (entry.title.down ().contains (needle) || entry.uri.down ().contains (needle)) {
                filtered += entry;
            }
        }
        return filtered;
    }

    public void add_entry (string uri, string title, bool is_private = false) {
        if (is_private || !OBrowserUtils.should_track_history_uri (uri)) {
            return;
        }

        HistoryEntry[] entries = load_all ();
        bool updated = false;
        for (int i = 0; i < entries.length; i++) {
            if (entries[i].uri == uri) {
                entries[i].title = OBrowserUtils.clean_title (title, uri);
                entries[i].visited_at = OBrowserUtils.now_unix ();
                entries[i].visit_count += 1;
                updated = true;
                break;
            }
        }

        if (!updated) {
            entries += new HistoryEntry (uri, OBrowserUtils.clean_title (title, uri), OBrowserUtils.now_unix (), 1);
        }

        sort_entries (entries);
        if (entries.length > max_entries) {
            HistoryEntry[] trimmed = {};
            for (int i = 0; i < max_entries; i++) {
                trimmed += entries[i];
            }
            entries = trimmed;
        }
        save_all (entries);
    }

    public void delete_entry (string uri) {
        HistoryEntry[] filtered = {};
        foreach (HistoryEntry entry in load_all ()) {
            if (entry.uri != uri) {
                filtered += entry;
            }
        }
        save_all (filtered);
    }

    public void clear () {
        save_all ({ });
    }

    public bool rebuild_index_now () {
        if (!FileUtils.test (sidecar_path, FileTest.EXISTS)) {
            return false;
        }
        string cmd = "%s %s %s".printf (Shell.quote (sidecar_path), Shell.quote (path), Shell.quote (index_path));
        try {
            int status;
            Process.spawn_command_line_sync (cmd, null, null, out status);
            return status == 0;
        } catch (Error error) {
            return false;
        }
    }

    private void save_all (HistoryEntry[] entries) {
        var key_file = new KeyFile ();
        for (int i = 0; i < entries.length; i++) {
            string group = "history-%03d".printf (i);
            key_file.set_string (group, "uri", entries[i].uri);
            key_file.set_string (group, "title", entries[i].title);
            key_file.set_int64 (group, "visited_at", entries[i].visited_at);
            key_file.set_integer (group, "visit_count", entries[i].visit_count);
        }
        OBrowserUtils.write_key_file (path, key_file);
    }

    private void sort_entries (HistoryEntry[] entries) {
        for (int i = 0; i < entries.length; i++) {
            for (int j = i + 1; j < entries.length; j++) {
                if (entries[j].visited_at > entries[i].visited_at) {
                    HistoryEntry temp = entries[i];
                    entries[i] = entries[j];
                    entries[j] = temp;
                }
            }
        }
    }

    private string get_string (KeyFile key_file, string group, string key) {
        try { return key_file.get_string (group, key); } catch (Error error) { return ""; }
    }
    private int64 get_int64 (KeyFile key_file, string group, string key) {
        try { return key_file.get_int64 (group, key); } catch (Error error) { return 0; }
    }
    private int get_int (KeyFile key_file, string group, string key, int fallback) {
        try { return key_file.get_integer (group, key); } catch (Error error) { return fallback; }
    }
}
