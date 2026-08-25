using GLib;
using Gdk;

namespace OBrowserUtils {
    public int64 now_unix () {
        return new DateTime.now_local ().to_unix ();
    }

    public void ensure_directory (string path) {
        if (path.strip () == "") {
            return;
        }
        try {
            File.new_for_path (path).make_directory_with_parents ();
        } catch (Error error) {
        }
    }

    public void ensure_file_exists (string path) {
        ensure_directory (Path.get_dirname (path));
        if (FileUtils.test (path, FileTest.EXISTS)) {
            return;
        }
        try {
            FileUtils.set_contents (path, "");
        } catch (Error error) {
        }
    }

    public KeyFile load_key_file_safe (string path) {
        ensure_file_exists (path);
        var key_file = new KeyFile ();
        try {
            key_file.load_from_file (path, KeyFileFlags.NONE);
        } catch (Error error) {
            try {
                FileUtils.set_contents (path, "");
            } catch (Error ignored) {
            }
        }
        return key_file;
    }

    public bool write_key_file (string path, KeyFile key_file) {
        ensure_directory (Path.get_dirname (path));
        try {
            size_t length = 0;
            string data = key_file.to_data (out length);
            FileUtils.set_contents (path, data, (ssize_t) length);
            return true;
        } catch (Error error) {
            return false;
        }
    }

    public string clean_title (string title, string fallback) {
        string value = title.strip ();
        return value != "" ? value : fallback;
    }

    public string format_timestamp (int64 unix_time) {
        if (unix_time <= 0) {
            return "Unknown time";
        }
        return new DateTime.from_unix_local (unix_time).format ("%Y-%m-%d %H:%M:%S");
    }

    public string sanitize_filename (string name) {
        StringBuilder builder = new StringBuilder ();
        for (int i = 0; i < name.length; i++) {
            unichar c = name.get_char (i);
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_') {
                builder.append_unichar (c);
            } else {
                builder.append_c ('_');
            }
        }

        string safe = builder.str.strip ();
        return safe != "" ? safe : "download.bin";
    }

    public string build_unique_path (string directory, string filename) {
        ensure_directory (directory);
        string path = Path.build_filename (directory, filename);
        if (!FileUtils.test (path, FileTest.EXISTS)) {
            return path;
        }

        string basename = filename;
        string extension = "";
        int dot_index = filename.last_index_of_char ('.');
        if (dot_index > 0) {
            basename = filename.substring (0, dot_index);
            extension = filename.substring (dot_index);
        }

        for (int i = 1; i < 1000; i++) {
            path = Path.build_filename (directory, "%s-%d%s".printf (basename, i, extension));
            if (!FileUtils.test (path, FileTest.EXISTS)) {
                return path;
            }
        }

        return Path.build_filename (directory, "%s-%ld%s".printf (basename, (long) now_unix (), extension));
    }

    public bool is_probable_url (string value) {
        string input = value.strip ();
        if (input == "" || input.contains (" ")) {
            return false;
        }

        if (input.has_prefix ("http://") || input.has_prefix ("https://") || input.has_prefix ("file://") || input.has_prefix ("about:") || input.has_prefix ("obrowser://")) {
            return true;
        }

        if (input.has_prefix ("localhost") || input.has_prefix ("127.") || input.has_prefix ("[::1]")) {
            return true;
        }

        return input.contains (".") || input.contains (":");
    }

    public string normalize_home_page (string value, string fallback = "about:blank") {
        string input = value.strip ();
        if (input == "") {
            return fallback;
        }
        if (input == "about:blank" || input.has_prefix ("obrowser://")) {
            return input;
        }
        if (input.has_prefix ("http://") || input.has_prefix ("https://") || input.has_prefix ("file://")) {
            return input;
        }
        if (is_probable_url (input)) {
            return input.has_prefix ("localhost") || input.has_prefix ("127.") || input.contains (":") || input.contains (".") ? "https://" + input : fallback;
        }
        return fallback;
    }

    public bool should_track_history_uri (string uri) {
        string clean = uri.strip ();
        if (clean == "" || clean == "about:blank") {
            return false;
        }
        if (clean.has_prefix ("obrowser://") || clean.has_prefix ("data:text/html")) {
            return false;
        }
        return true;
    }

    public bool should_save_session_uri (string uri) {
        string clean = uri.strip ();
        if (clean == "" || clean == "about:blank") {
            return false;
        }
        return !clean.has_prefix ("obrowser://");
    }

    public string permission_label (WebKit.PermissionRequest request) {
        if (request is WebKit.GeolocationPermissionRequest) {
            return "Location";
        }
        if (request is WebKit.NotificationPermissionRequest) {
            return "Notifications";
        }
        if (request is WebKit.UserMediaPermissionRequest) {
            return "Camera / microphone";
        }
        if (request is WebKit.DeviceInfoPermissionRequest) {
            return "Device info";
        }
        if (request is WebKit.WebsiteDataAccessPermissionRequest) {
            return "Website data access";
        }
        return "Site permission";
    }

    public string find_tool (string rel) {
        string[] candidates = {};
        string exe_dir = "";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            if (exe != "") {
                exe_dir = Path.get_dirname (exe);
            }
        } catch (Error error) {
        }
        if (exe_dir == "") {
            exe_dir = Environment.get_current_dir ();
        }
        candidates += Path.build_filename (exe_dir, rel);
        candidates += Path.build_filename (exe_dir, "..", rel);
        candidates += Path.build_filename (exe_dir, "..", "lib", "obrowser", rel);
        candidates += Path.build_filename (exe_dir, "..", "share", "obrowser", rel);
        candidates += Path.build_filename (Environment.get_current_dir (), rel);
        foreach (string c in candidates) {
            if (FileUtils.test (c, FileTest.EXISTS)) {
                return c;
            }
        }
        return candidates[0];
    }

    public string json_string (string value) {
        var builder = new StringBuilder ();
        builder.append_c ('"');
        int i = 0;
        while (i < value.length) {
            unichar c = value.get_char (i);
            if (c == '"') {
                builder.append ("\\\"");
            } else if (c == '\\') {
                builder.append ("\\\\");
            } else if (c == '\n') {
                builder.append ("\\n");
            } else if (c == '\r') {
                builder.append ("\\r");
            } else if (c == '\t') {
                builder.append ("\\t");
            } else if (c < 0x20) {
                builder.append ("\\u");
                builder.append ("%04x".printf ((int) c));
            } else {
                builder.append_unichar (c);
            }
            i += c.to_string ().length;
        }
        builder.append_c ('"');
        return builder.str;
    }

    public Gdk.Pixbuf? pixbuf_from_surface (Cairo.Surface? surface) {
        if (surface == null) {
            return null;
        }
        return Gdk.pixbuf_get_from_surface (surface, 0, 0, 16, 16);
    }

    public string origin_from_uri (string uri) {
        string clean = uri.strip ();
        if (clean == "") {
            return "";
        }

        try {
            Uri parsed = Uri.parse (clean, UriFlags.NONE);
            string scheme = parsed.get_scheme () ?? "";
            string host = parsed.get_host () ?? "";
            int port = parsed.get_port ();
            if (scheme != "" && host != "") {
                if (port > 0) {
                    return "%s://%s:%d".printf (scheme, host, port);
                }
                return "%s://%s".printf (scheme, host);
            }
        } catch (Error error) {
        }
        return "";
    }
}
