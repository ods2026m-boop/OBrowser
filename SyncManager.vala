using GLib;

public class SyncManager : Object {
    private AppPaths paths;

    public SyncManager (AppPaths paths) {
        this.paths = paths;
    }

    public bool sync_now (string endpoint, string token) {
        string script = OBrowserUtils.find_tool ("tools/sync_client.lua");
        if (!FileUtils.test (script, FileTest.EXISTS)) {
            return false;
        }

        // The token is passed via an environment variable so it never appears
        // on the command line (and is therefore not visible to ps / /proc).
        string cmd = "OBROWSER_SYNC_TOKEN=%s lua %s %s %s %s %s".printf (
            Shell.quote (token),
            Shell.quote (script),
            Shell.quote (endpoint),
            Shell.quote (paths.bookmarks_file ()),
            Shell.quote (paths.history_file ()),
            Shell.quote (paths.settings_file ())
        );

        try {
            int status;
            Process.spawn_command_line_sync (cmd, null, null, out status);
            return status == 0;
        } catch (Error error) {
            return false;
        }
    }
}
