using GLib;

public class CrashReporter : Object {
    private string log_path;
    private bool writing = false;

    public CrashReporter (AppPaths paths) {
        log_path = Path.build_filename (paths.cache_dir, "crash.log");
    }

    public void install () {
        GLib.Log.set_default_handler ((domain, level, message) => {
            if ((level & LogLevelFlags.LEVEL_ERROR) != 0 || (level & LogLevelFlags.LEVEL_CRITICAL) != 0 || (level & LogLevelFlags.LEVEL_WARNING) != 0) {
                string safe_message = message ?? "(null)";
                append_line ("[%s] %s: %s".printf (new DateTime.now_local ().format ("%Y-%m-%d %H:%M:%S"), domain ?? "app", safe_message));
            }
            GLib.Log.default_handler (domain, level, message);
        });
    }

    public void log_event (string message) {
        append_line ("[%s] INFO: %s".printf (new DateTime.now_local ().format ("%Y-%m-%d %H:%M:%S"), message));
    }

    public string get_log_path () {
        return log_path;
    }

    public void upload_latest_async (string endpoint, string token) {
        string script = OBrowserUtils.find_tool ("tools/crash_uploader.lua");
        if (!FileUtils.test (script, FileTest.EXISTS)) {
            return;
        }
        string cmd = "lua %s %s %s %s".printf (Shell.quote (script), Shell.quote (log_path), Shell.quote (endpoint), Shell.quote (token));
        try {
            Process.spawn_command_line_async (cmd);
        } catch (Error error) {
        }
    }

    private void append_line (string line) {
        if (writing) {
            return;
        }
        writing = true;

        FileStream? stream = FileStream.open (log_path, "a");
        if (stream != null) {
            stream.puts (line + "\n");
        }
        writing = false;
    }
}
