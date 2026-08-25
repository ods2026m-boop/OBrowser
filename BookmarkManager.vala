using GLib;

public class BookmarkManager : Object {
    private string path;

    public BookmarkManager (AppPaths app_paths) {
        path = app_paths.bookmarks_file ();
        OBrowserUtils.ensure_file_exists (path);
    }

    public BookmarkEntry[] load_all () {
        var key_file = OBrowserUtils.load_key_file_safe (path);
        BookmarkEntry[] entries = {};
        foreach (string group in key_file.get_groups ()) {
            string uri = get_string (key_file, group, "uri");
            if (uri == "") {
                continue;
            }
            entries += new BookmarkEntry (uri, get_string (key_file, group, "title"), get_int64 (key_file, group, "added_at"));
        }
        sort_entries (entries);
        return entries;
    }

    public BookmarkEntry[] search (string query) {
        string needle = query.strip ().down ();
        if (needle == "") {
            return load_all ();
        }
        BookmarkEntry[] filtered = {};
        foreach (BookmarkEntry entry in load_all ()) {
            if (entry.title.down ().contains (needle) || entry.uri.down ().contains (needle)) {
                filtered += entry;
            }
        }
        return filtered;
    }

    public bool contains (string uri) {
        foreach (BookmarkEntry entry in load_all ()) {
            if (entry.uri == uri) {
                return true;
            }
        }
        return false;
    }

    public void add_or_update (string uri, string title) {
        if (uri.strip () == "") {
            return;
        }

        BookmarkEntry[] entries = load_all ();
        bool updated = false;
        for (int i = 0; i < entries.length; i++) {
            if (entries[i].uri == uri) {
                entries[i].title = OBrowserUtils.clean_title (title, uri);
                entries[i].added_at = OBrowserUtils.now_unix ();
                updated = true;
                break;
            }
        }

        if (!updated) {
            entries += new BookmarkEntry (uri, OBrowserUtils.clean_title (title, uri), OBrowserUtils.now_unix ());
        }

        save_all (entries);
    }

    public void update_entry (string original_uri, string new_title, string new_uri) {
        BookmarkEntry[] entries = load_all ();
        for (int i = 0; i < entries.length; i++) {
            if (entries[i].uri == original_uri) {
                entries[i].uri = new_uri.strip () != "" ? new_uri.strip () : original_uri;
                entries[i].title = OBrowserUtils.clean_title (new_title, entries[i].uri);
                entries[i].added_at = OBrowserUtils.now_unix ();
                break;
            }
        }
        save_all (entries);
    }

    public void remove (string uri) {
        BookmarkEntry[] filtered = {};
        foreach (BookmarkEntry entry in load_all ()) {
            if (entry.uri != uri) {
                filtered += entry;
            }
        }
        save_all (filtered);
    }

    public bool export_to_file (string destination) {
        var key_file = new KeyFile ();
        BookmarkEntry[] entries = load_all ();
        for (int i = 0; i < entries.length; i++) {
            string group = "bookmark-%03d".printf (i);
            key_file.set_string (group, "uri", entries[i].uri);
            key_file.set_string (group, "title", entries[i].title);
            key_file.set_int64 (group, "added_at", entries[i].added_at);
        }
        return OBrowserUtils.write_key_file (destination, key_file);
    }

    public bool import_from_file (string source) {
        var key_file = OBrowserUtils.load_key_file_safe (source);
        BookmarkEntry[] merged = load_all ();
        foreach (string group in key_file.get_groups ()) {
            string uri = get_string (key_file, group, "uri");
            if (uri == "") {
                continue;
            }
            string title = get_string (key_file, group, "title");
            bool exists = false;
            foreach (BookmarkEntry entry in merged) {
                if (entry.uri == uri) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                merged += new BookmarkEntry (uri, OBrowserUtils.clean_title (title, uri), OBrowserUtils.now_unix ());
            }
        }
        save_all (merged);
        return true;
    }

    private void save_all (BookmarkEntry[] entries) {
        var key_file = new KeyFile ();
        sort_entries (entries);
        for (int i = 0; i < entries.length; i++) {
            string group = "bookmark-%03d".printf (i);
            key_file.set_string (group, "uri", entries[i].uri);
            key_file.set_string (group, "title", entries[i].title);
            key_file.set_int64 (group, "added_at", entries[i].added_at);
        }
        OBrowserUtils.write_key_file (path, key_file);
    }

    private void sort_entries (BookmarkEntry[] entries) {
        for (int i = 0; i < entries.length; i++) {
            for (int j = i + 1; j < entries.length; j++) {
                if (entries[j].added_at > entries[i].added_at) {
                    BookmarkEntry temp = entries[i];
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
}
