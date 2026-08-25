using GLib;

public class AppPaths : Object {
    public string config_dir { get; private set; }
    public string data_dir { get; private set; }
    public string cache_dir { get; private set; }

    public AppPaths () {
        config_dir = Path.build_filename (Environment.get_user_config_dir (), "obrowser");
        data_dir = Path.build_filename (Environment.get_user_data_dir (), "obrowser");
        cache_dir = Path.build_filename (Environment.get_user_cache_dir (), "obrowser");
        ensure_all (); 
    }

    public void ensure_all () {
        OBrowserUtils.ensure_directory (config_dir);
        OBrowserUtils.ensure_directory (data_dir);
        OBrowserUtils.ensure_directory (cache_dir);
    }

    public string settings_file () { return Path.build_filename (config_dir, "settings.ini"); }
    public string bookmarks_file () { return Path.build_filename (data_dir, "bookmarks.ini"); }
    public string history_file () { return Path.build_filename (data_dir, "history.ini"); }
    public string downloads_file () { return Path.build_filename (data_dir, "downloads.ini"); }
    public string session_file () { return Path.build_filename (cache_dir, "session.ini"); }
    public string export_dir () { return data_dir; }

    public string default_download_dir () {
        string? special = Environment.get_user_special_dir (UserDirectory.DOWNLOAD);
        if (special != null && special.strip () != "") {
            OBrowserUtils.ensure_directory (special);
            return special;
        }

        string fallback = Path.build_filename (data_dir, "downloads");
        OBrowserUtils.ensure_directory (fallback);
        return fallback;
    }
}
