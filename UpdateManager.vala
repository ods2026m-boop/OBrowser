using GLib;

public class UpdateInfo : Object {
    public string current_version { get; set; default = "0.1.0"; }
    public string latest_version { get; set; default = "0.1.0"; }
    public string channel { get; set; default = "stable"; }
    public string notes { get; set; default = ""; }
    public string url { get; set; default = ""; }
    public bool update_available { get; set; default = false; }
}

public class UpdateManager : Object {
    private string state_path;
    private string rollback_state_path;
    private string pinned_pubkey_path;

    public UpdateManager (AppPaths paths) {
        state_path = Path.build_filename (paths.cache_dir, "update_state.ini");
        rollback_state_path = Path.build_filename (paths.cache_dir, "update_last_seen.txt");
        pinned_pubkey_path = Path.build_filename (paths.config_dir, "update_pubkey.pem");
        OBrowserUtils.ensure_file_exists (state_path);
    }

    public UpdateInfo check_now (string manifest_url, string channel, string current_version, string pinned_pubkey, string next_pubkey, bool allow_rotation) {
        var info = new UpdateInfo ();
        info.current_version = current_version;
        info.channel = channel;

        string secure_script = OBrowserUtils.find_tool ("tools/update_secure.lua");
        if (!FileUtils.test (secure_script, FileTest.EXISTS)) {
            warning ("Secure update tool not available at %s; refusing to check for updates. Rebuild the Nim/Lua tools.", secure_script);
            return info;
        }

        string cmd = "lua %s %s %s %s %s %s %s %s".printf (
            Shell.quote (secure_script),
            Shell.quote (manifest_url),
            Shell.quote (channel),
            Shell.quote (current_version),
            Shell.quote (pinned_pubkey.strip () != "" ? pinned_pubkey : pinned_pubkey_path),
            Shell.quote (next_pubkey),
            Shell.quote (allow_rotation ? "true" : "false"),
            Shell.quote (rollback_state_path)
        );
        try {
            string stdout_text;
            string stderr_text;
            int status;
            Process.spawn_command_line_sync (cmd, out stdout_text, out stderr_text, out status);
            if (status == 0) {
                parse_output (info, stdout_text);
                persist (info);
            }
        } catch (Error error) {
        }

        return info;
    }

    private void parse_output (UpdateInfo info, string output) {
        foreach (string line in output.split ("\n")) {
            string[] parts = line.split ("=", 2);
            if (parts.length != 2) {
                continue;
            }
            string key = parts[0].strip ();
            string val = parts[1].strip ();
            if (key == "latest_version") info.latest_version = val;
            if (key == "notes") info.notes = val;
            if (key == "url") info.url = val;
            if (key == "update_available") info.update_available = val == "true";
            if (key == "rotated_pubkey" && val != "") info.notes = "%s (key rotated)".printf (info.notes);
        }
    }

    private void persist (UpdateInfo info) {
        var key_file = new KeyFile ();
        key_file.set_string ("update", "current", info.current_version);
        key_file.set_string ("update", "latest", info.latest_version);
        key_file.set_string ("update", "channel", info.channel);
        key_file.set_string ("update", "notes", info.notes);
        key_file.set_string ("update", "url", info.url);
        key_file.set_boolean ("update", "available", info.update_available);
        OBrowserUtils.write_key_file (state_path, key_file);
    }
}
