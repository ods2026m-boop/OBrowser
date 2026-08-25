using GLib;

public enum StartupBehavior {
    HOME_PAGE,
    RESTORE_SESSION,
    BLANK_PAGE;

    public string to_key () {
        switch (this) {
        case HOME_PAGE:
            return "home";
        case RESTORE_SESSION:
            return "restore";
        case BLANK_PAGE:
            return "blank";
        }
        return "home";
    }

    public static StartupBehavior from_key (string value) {
        switch (value.down ()) {
        case "restore":
            return RESTORE_SESSION;
        case "blank":
            return BLANK_PAGE;
        default:
            return HOME_PAGE;
        }
    }
}

public class SearchEngine : Object {
    public string id { get; construct; }
    public string name { get; construct; }
    public string search_url_template { get; construct; }

    public SearchEngine (string id, string name, string search_url_template) {
        Object (id: id, name: name, search_url_template: search_url_template);
    }

    public string build_search_url (string query) {
        return search_url_template.replace ("{query}", Uri.escape_string (query, null, true));
    }
}

public class BookmarkEntry : Object {
    public string uri { get; set; }
    public string title { get; set; }
    public int64 added_at { get; set; }

    public BookmarkEntry (string uri, string title, int64 added_at) {
        this.uri = uri;
        this.title = title;
        this.added_at = added_at;
    }
}

public class HistoryEntry : Object {
    public string uri { get; set; }
    public string title { get; set; }
    public int64 visited_at { get; set; }
    public int visit_count { get; set; }

    public HistoryEntry (string uri, string title, int64 visited_at, int visit_count = 1) {
        this.uri = uri;
        this.title = title;
        this.visited_at = visited_at;
        this.visit_count = visit_count;
    }
}

public class DownloadEntry : Object {
    public string id { get; set; }
    public string uri { get; set; }
    public string destination { get; set; }
    public string status { get; set; }
    public double progress { get; set; }
    public int64 updated_at { get; set; }
    public bool is_private { get; set; }

    public DownloadEntry (string id, string uri, string destination, string status, double progress, int64 updated_at, bool is_private = false) {
        this.id = id;
        this.uri = uri;
        this.destination = destination;
        this.status = status;
        this.progress = progress;
        this.updated_at = updated_at;
        this.is_private = is_private;
    }
}

public class SessionState : Object {
    public string[] uris { get; set; default = {}; }
    public int active_index { get; set; default = 0; }
}

public class BrowserSettings : Object {
    public string home_page { get; set; default = "https://www.google.com/"; }
    public string search_engine_id { get; set; default = "google"; }
    public StartupBehavior startup_behavior { get; set; default = StartupBehavior.RESTORE_SESSION; }
    public bool restore_session { get; set; default = true; }
    public string download_directory { get; set; default = ""; }
    public bool ask_download_location { get; set; default = false; }
    public double default_zoom_level { get; set; default = 1.0; }
    public bool show_status_bar { get; set; default = true; }
    public bool show_bookmarks_bar { get; set; default = false; }
    public string ui_theme { get; set; default = "light"; }
    public bool save_history { get; set; default = true; }
    public bool enable_javascript { get; set; default = true; }
    public bool enable_images { get; set; default = true; }
    public bool enable_developer_tools { get; set; default = true; }
    public string user_agent { get; set; default = ""; }
    public string update_manifest_url { get; set; default = ""; }
    public string update_channel { get; set; default = "stable"; }
    public string update_pinned_pubkey { get; set; default = ""; }
    public string update_next_pubkey { get; set; default = ""; }
    public bool update_allow_key_rotation { get; set; default = false; }
    public string sync_endpoint { get; set; default = ""; }
    public string sync_token { get; set; default = ""; }
    public string crash_endpoint { get; set; default = ""; }
    public string crash_token { get; set; default = ""; }
}
