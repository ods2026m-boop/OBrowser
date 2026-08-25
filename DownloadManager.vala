using GLib;
using WebKit;
using Gtk;

public class DownloadManager : Object {
    public signal void changed ();
    public signal void status_message (string message);

    private string path;
    private SettingsManager settings_manager;
    private SecurityManager security_manager;
    private Download[] active_downloads = {};
    private string[] active_ids = {};
    private static int download_seq = 0;
    private DownloadEntry[] private_entries = {};

    public DownloadManager (AppPaths app_paths, SettingsManager settings_manager, SecurityManager security_manager) {
        this.path = app_paths.downloads_file ();
        this.settings_manager = settings_manager;
        this.security_manager = security_manager;
        OBrowserUtils.ensure_file_exists (path);
    }

    public DownloadEntry[] load_all () {
        var key_file = OBrowserUtils.load_key_file_safe (path);
        DownloadEntry[] entries = {};
        foreach (string group in key_file.get_groups ()) {
            entries += new DownloadEntry (
                group,
                get_string (key_file, group, "uri"),
                get_string (key_file, group, "destination"),
                get_string (key_file, group, "status"),
                get_double (key_file, group, "progress"),
                get_int64 (key_file, group, "updated_at"),
                get_bool (key_file, group, "is_private", false)
            );
        }
        sort_entries (entries);
        return entries;
    }

    public DownloadEntry[] list_entries () {
        DownloadEntry[] entries = load_all ();
        foreach (DownloadEntry entry in private_entries) {
            entries += entry;
        }
        sort_entries (entries);
        return entries;
    }

    public void attach_to_context (WebContext context, bool is_private, Gtk.Window parent) {
        context.download_started.connect ((download) => {
            handle_download (download, is_private, parent);
        });
    }

    public void cancel (string id) {
        for (int i = 0; i < active_ids.length; i++) {
            if (active_ids[i] == id) {
                active_downloads[i].cancel ();
                break;
            }
        }
    }

    public void clear_completed () {
        DownloadEntry[] kept = {};
        foreach (DownloadEntry entry in load_all ()) {
            if (entry.status != "completed") {
                kept += entry;
            }
        }
        DownloadEntry[] kept_private = {};
        foreach (DownloadEntry entry in private_entries) {
            if (entry.status != "completed") {
                kept_private += entry;
            }
        }
        private_entries = kept_private;
        save_all (kept);
        changed ();
    }

    public void clear_all () {
        private_entries = {};
        save_all ({});
        changed ();
    }

    public void open_download (Gtk.Window parent, string destination) {
        if (destination.strip () == "") {
            return;
        }
        try {
            Gtk.show_uri_on_window (parent, File.new_for_path (destination).get_uri (), Gdk.CURRENT_TIME);
        } catch (Error error) {
            status_message ("Unable to open file: %s".printf (destination));
        }
    }

    public void open_folder (Gtk.Window parent, string destination) {
        string target = destination.strip () != "" ? Path.get_dirname (destination) : settings_manager.download_directory;
        try {
            Gtk.show_uri_on_window (parent, File.new_for_path (target).get_uri (), Gdk.CURRENT_TIME);
        } catch (Error error) {
            status_message ("Unable to open folder: %s".printf (target));
        }
    }

    private void handle_download (Download download, bool is_private, Gtk.Window parent) {
        string id = "download-%ld-%d".printf ((long) OBrowserUtils.now_unix (), ++download_seq);
        string[] destination_path = { "" };
        string source_uri = "";

        active_downloads += download;
        active_ids += id;

        URIRequest? request = download.get_request ();
        if (request != null && request.get_uri () != null) {
            source_uri = request.get_uri ();
        }
        string blocked_reason = "";
        if (security_manager.should_block (source_uri, "", out blocked_reason)) {
            download.cancel ();
            status_message ("Blocked download: %s".printf (blocked_reason));
            return;
        }

        download.decide_destination.connect ((suggested_filename) => {
            string directory = settings_manager.download_directory;
            OBrowserUtils.ensure_directory (directory);
            string name = suggested_filename.strip () != "" ? suggested_filename : Path.get_basename (source_uri);
            if (name == null || name.strip () == "") {
                name = "download.bin";
            }

            string destination = choose_destination (parent, directory, name);
            if (destination.strip () == "") {
                download.cancel ();
                return true;
            }

            destination_path[0] = destination;
            download.set_destination (File.new_for_path (destination).get_uri ());
            upsert (new DownloadEntry (id, source_uri, destination, "running", 0.0, OBrowserUtils.now_unix (), is_private), !is_private);
            changed ();
            return true;
        });

        download.notify["estimated-progress"].connect (() => {
            upsert (new DownloadEntry (id, source_uri, destination_path[0], "running", download.estimated_progress, OBrowserUtils.now_unix (), is_private), !is_private);
            changed ();
        });

        download.finished.connect (() => {
            upsert (new DownloadEntry (id, source_uri, destination_path[0], "completed", 1.0, OBrowserUtils.now_unix (), is_private), !is_private);
            remove_active (id);
            changed ();
            status_message ("Download completed: %s".printf (destination_path[0]));
        });

        download.failed.connect ((error) => {
            string destination = destination_path[0];
            if (destination.strip () != "") {
                delete_partial_file (destination);
            }
            upsert (new DownloadEntry (id, source_uri, destination, "failed", download.estimated_progress, OBrowserUtils.now_unix (), is_private), !is_private);
            remove_active (id);
            changed ();
            status_message ("Download failed: %s".printf (source_uri));
        });
    }

    private string choose_destination (Gtk.Window parent, string directory, string filename) {
        if (!settings_manager.ask_download_location) {
            return OBrowserUtils.build_unique_path (directory, OBrowserUtils.sanitize_filename (filename));
        }

        var dialog = new FileChooserDialog ("Save Download", parent, FileChooserAction.SAVE,
            "_Cancel", ResponseType.CANCEL,
            "_Save", ResponseType.ACCEPT);
        dialog.do_overwrite_confirmation = true;
        dialog.set_current_folder (directory);
        dialog.set_current_name (OBrowserUtils.sanitize_filename (filename));

        string destination = "";
        if (dialog.run () == (int) ResponseType.ACCEPT) {
            destination = dialog.get_filename () ?? "";
        }
        dialog.destroy ();
        return destination;
    }

    private void delete_partial_file (string destination) {
        if (destination == null || destination.strip () == "") {
            return;
        }
        try {
            var file = File.new_for_path (destination);
            if (file.query_exists ()) {
                file.delete ();
            }
        } catch (Error error) {
            warning ("Failed to delete partial download %s: %s".printf (destination, error.message));
        }
    }

    private void remove_active (string id) {
        Download[] new_downloads = {};
        string[] new_ids = {};
        for (int i = 0; i < active_ids.length; i++) {
            if (active_ids[i] != id) {
                new_ids += active_ids[i];
                new_downloads += active_downloads[i];
            }
        }
        active_ids = new_ids;
        active_downloads = new_downloads;
    }

    private void upsert (DownloadEntry entry, bool persist) {
        if (!persist) {
            bool updated_private = false;
            for (int i = 0; i < private_entries.length; i++) {
                if (private_entries[i].id == entry.id) {
                    private_entries[i] = entry;
                    updated_private = true;
                    break;
                }
            }
            if (!updated_private) {
                private_entries += entry;
            }
            return;
        }

        DownloadEntry[] entries = load_all ();
        bool updated = false;
        for (int i = 0; i < entries.length; i++) {
            if (entries[i].id == entry.id) {
                entries[i] = entry;
                updated = true;
                break;
            }
        }
        if (!updated) {
            entries += entry;
        }
        save_all (entries);
    }

    private void save_all (DownloadEntry[] entries) {
        var key_file = new KeyFile ();
        for (int i = 0; i < entries.length; i++) {
            key_file.set_string (entries[i].id, "uri", entries[i].uri);
            key_file.set_string (entries[i].id, "destination", entries[i].destination);
            key_file.set_string (entries[i].id, "status", entries[i].status);
            key_file.set_double (entries[i].id, "progress", entries[i].progress);
            key_file.set_int64 (entries[i].id, "updated_at", entries[i].updated_at);
            key_file.set_boolean (entries[i].id, "is_private", entries[i].is_private);
        }
        OBrowserUtils.write_key_file (path, key_file);
    }

    private void sort_entries (DownloadEntry[] entries) {
        for (int i = 0; i < entries.length; i++) {
            for (int j = i + 1; j < entries.length; j++) {
                if (entries[j].updated_at > entries[i].updated_at) {
                    DownloadEntry temp = entries[i];
                    entries[i] = entries[j];
                    entries[j] = temp;
                }
            }
        }
    }

    private string get_string (KeyFile key_file, string group, string key) { try { return key_file.get_string (group, key); } catch (Error error) { return ""; } }
    private double get_double (KeyFile key_file, string group, string key) { try { return key_file.get_double (group, key); } catch (Error error) { return 0.0; } }
    private int64 get_int64 (KeyFile key_file, string group, string key) { try { return key_file.get_int64 (group, key); } catch (Error error) { return 0; } }
    private bool get_bool (KeyFile key_file, string group, string key, bool fallback) { try { return key_file.get_boolean (group, key); } catch (Error error) { return fallback; } }
}
