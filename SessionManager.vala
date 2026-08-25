using GLib;

public class SessionManager : Object {
    private string path;

    public SessionManager (AppPaths app_paths) {
        path = app_paths.session_file ();
        OBrowserUtils.ensure_file_exists (path);
    }

    public SessionState load () {
        var state = new SessionState ();
        var key_file = OBrowserUtils.load_key_file_safe (path);
        try {
            state.active_index = key_file.get_integer ("session", "active_index");
        } catch (Error error) {
            state.active_index = 0;
        }

        int count = 0;
        try {
            count = key_file.get_integer ("session", "count");
        } catch (Error error) {
            count = 0;
        }

        string[] uris = {};
        for (int i = 0; i < count; i++) {
            try {
                string value = key_file.get_string ("session", "tab-%d".printf (i));
                if (should_restore_session_uri (value)) {
                    uris += value;
                }
            } catch (Error error) {
            }
        }
        state.uris = uris;
        if (state.active_index < 0 || state.active_index >= state.uris.length) {
            state.active_index = 0;
        }
        return state;
    }

    private static bool should_restore_session_uri (string uri) {
        string clean = uri.strip ();
        if (clean == "") {
            return false;
        }
        if (!OBrowserUtils.should_save_session_uri (uri)) {
            return false;
        }
        string[] dangerous_schemes = { "javascript:", "data:text/html", "vbscript:" };
        foreach (string scheme in dangerous_schemes) {
            if (clean.down ().has_prefix (scheme)) {
                return false;
            }
        }
        return true;
    }

    public void save (string[] uris, int active_index) {
        var key_file = new KeyFile ();
        key_file.set_integer ("session", "active_index", active_index < 0 ? 0 : active_index);
        key_file.set_integer ("session", "count", uris.length);
        for (int i = 0; i < uris.length; i++) {
            key_file.set_string ("session", "tab-%d".printf (i), uris[i]);
        }
        OBrowserUtils.write_key_file (path, key_file);
    }

    public void clear () {
        save ({}, 0);
    }
}
