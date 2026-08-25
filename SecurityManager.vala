using GLib;

public class SecurityManager : Object {
    private string guard_path;
    private string blocklist_path;
    private string whitelist_path;
    private string audit_log_path;
    private HashTable<string,string> verdict_cache;
    private string rules_stamp = "";

    public SecurityManager (AppPaths paths) {
        guard_path = OBrowserUtils.find_tool ("build/security_guard");
        blocklist_path = Path.build_filename (paths.config_dir, "security_blocklist.txt");
        whitelist_path = Path.build_filename (paths.config_dir, "security_whitelist.txt");
        audit_log_path = Path.build_filename (paths.cache_dir, "security_audit.log");
        verdict_cache = new HashTable<string,string> (str_hash, str_equal);
        ensure_rules_files ();
    }

    public bool should_block (string uri, string source_uri, out string reason) {
        reason = "";
        string clean = uri.strip ();
        string source = source_uri.strip ();
        if (clean == "") {
            return false;
        }
        invalidate_cache_if_rules_changed ();

        string cache_key = "%s|%s".printf (clean, source);
        string? cached = verdict_cache.lookup (cache_key);
        if (cached != null) {
            if (cached.has_prefix ("BLOCK:")) {
                reason = cached.substring (6);
                return true;
            }
            return false;
        }

        bool guard_missing = !FileUtils.test (guard_path, FileTest.EXISTS);
        if (guard_missing) {
            if (fallback_should_block (clean, source, out reason)) {
                verdict_cache.insert (cache_key, "BLOCK:" + reason);
                return true;
            }
            verdict_cache.insert (cache_key, "ALLOW");
            return false;
        }

        string cmd = "%s %s %s %s %s".printf (Shell.quote (guard_path), Shell.quote (clean), Shell.quote (blocklist_path), Shell.quote (whitelist_path), Shell.quote (source));
        bool guard_failed = false;
        bool block = false;
        bool saw_decision = false;
        string risk = "low";
        string graph = "";
        try {
            string stdout_text;
            string stderr_text;
            int status;
            Process.spawn_command_line_sync (cmd, out stdout_text, out stderr_text, out status);
            if (status == 0) {
                foreach (string line in stdout_text.split ("\n")) {
                    if (line.has_prefix ("decision=")) {
                        saw_decision = true;
                        block = line.substring (9).strip () == "block";
                    }
                    if (line.has_prefix ("reason=")) {
                        reason = line.substring (7).strip ();
                    }
                    if (line.has_prefix ("risk=")) {
                        risk = line.substring (5).strip ();
                    }
                    if (line.has_prefix ("policy_graph=")) {
                        graph = line.substring (13).strip ();
                    }
                }
            } else {
                guard_failed = true;
            }
        } catch (Error error) {
            guard_failed = true;
        }

        if (guard_failed || !saw_decision) {
            reason = "security guard unavailable; request blocked by default";
            write_audit_entry (clean, source, "block", reason, "high", "entry->guard_error->block");
            verdict_cache.insert (cache_key, "BLOCK:" + reason);
            return true;
        }

        write_audit_entry (clean, source, block ? "block" : "allow", reason, risk, graph);
        if (block) {
            verdict_cache.insert (cache_key, "BLOCK:" + reason);
            return true;
        }
        verdict_cache.insert (cache_key, "ALLOW");
        return false;
    }

    public string[] list_blocklist_entries () {
        return read_rules_entries (blocklist_path);
    }

    public string[] list_whitelist_entries () {
        return read_rules_entries (whitelist_path);
    }

    public void replace_blocklist_entries (string[] entries) {
        write_rules_entries (blocklist_path, "Blocked domains", entries);
    }

    public void replace_whitelist_entries (string[] entries) {
        write_rules_entries (whitelist_path, "Trusted domains (security exceptions)", entries);
    }

    public bool test_uri (string uri, string source_uri, out string reason) {
        return should_block (uri, source_uri, out reason);
    }

    public string[] audit_tail (int max_lines = 200) {
        string[] lines = {};
        try {
            string raw;
            FileUtils.get_contents (audit_log_path, out raw);
            foreach (string line in raw.split ("\n")) {
                if (line.strip () != "") {
                    lines += line;
                }
            }
        } catch (Error error) {
        }
        if (lines.length <= max_lines) {
            return lines;
        }
        string[] tail = {};
        for (int i = lines.length - max_lines; i < lines.length; i++) {
            tail += lines[i];
        }
        return tail;
    }

    public bool export_rules_json (string output_path) {
        string[] block = list_blocklist_entries ();
        string[] white = list_whitelist_entries ();
        StringBuilder b = new StringBuilder ();
        b.append ("{\n");
        b.append ("  \"version\": 1,\n");
        b.append ("  \"blocklist\": [\n");
        for (int i = 0; i < block.length; i++) {
            b.append ("    \"");
            b.append (escape_json (block[i]));
            b.append ("\"");
            if (i + 1 < block.length) {
                b.append (",");
            }
            b.append ("\n");
        }
        b.append ("  ],\n");
        b.append ("  \"whitelist\": [\n");
        for (int i = 0; i < white.length; i++) {
            b.append ("    \"");
            b.append (escape_json (white[i]));
            b.append ("\"");
            if (i + 1 < white.length) {
                b.append (",");
            }
            b.append ("\n");
        }
        b.append ("  ]\n");
        b.append ("}\n");
        try {
            FileUtils.set_contents (output_path, b.str);
            return true;
        } catch (Error error) {
            return false;
        }
    }

    public bool import_rules_json (string input_path) {
        try {
            string raw;
            FileUtils.get_contents (input_path, out raw);
            string[] block = extract_string_array_from_json (raw, "blocklist");
            string[] white = extract_string_array_from_json (raw, "whitelist");
            replace_blocklist_entries (block);
            replace_whitelist_entries (white);
            return true;
        } catch (Error error) {
            return false;
        }
    }

    private void ensure_rules_files () {
        ensure_rules_file (blocklist_path, "Blocked domains");
        ensure_rules_file (whitelist_path, "Trusted domains (security exceptions)");
        rules_stamp = compute_rules_stamp ();
    }

    private void ensure_rules_file (string path, string title) {
        if (FileUtils.test (path, FileTest.EXISTS)) {
            return;
        }
        string template = "# %s\n# One domain per line\n# example.org\n".printf (title);
        try {
            FileUtils.set_contents (path, template);
        } catch (Error error) {
        }
    }

    private string[] read_rules_entries (string path) {
        ensure_rules_files ();
        string[] entries = {};
        try {
            string content;
            FileUtils.get_contents (path, out content);
            foreach (string raw in content.split ("\n")) {
                string line = raw.strip ().down ();
                if (line == "" || line.has_prefix ("#")) {
                    continue;
                }
                entries += line;
            }
        } catch (Error error) {
        }
        return entries;
    }

    private void write_rules_entries (string path, string title, string[] entries) {
        ensure_rules_files ();
        HashTable<string,bool> seen = new HashTable<string,bool> (str_hash, str_equal);
        StringBuilder builder = new StringBuilder ();
        builder.append ("# ");
        builder.append (title);
        builder.append ("\n# One domain per line\n");
        foreach (string value in entries) {
            string clean = value.strip ().down ();
            if (clean == "" || clean.contains (" ") || seen.contains (clean)) {
                continue;
            }
            seen.insert (clean, true);
            builder.append (clean);
            builder.append_c ('\n');
        }
        try {
            FileUtils.set_contents (path, builder.str);
            rules_stamp = compute_rules_stamp ();
            verdict_cache.remove_all ();
        } catch (Error error) {
        }
    }

    private void invalidate_cache_if_rules_changed () {
        string current = compute_rules_stamp ();
        if (current == rules_stamp) {
            return;
        }
        rules_stamp = current;
        verdict_cache.remove_all ();
    }

    private string compute_rules_stamp () {
        return compute_file_stamp (blocklist_path) + "|" + compute_file_stamp (whitelist_path);
    }

    private string compute_file_stamp (string path) {
        try {
            File file = File.new_for_path (path);
            FileInfo info = file.query_info ("standard::size,time::modified,time::modified-usec", FileQueryInfoFlags.NONE);
            int64 modified = 0;
            DateTime? dt = info.get_modification_date_time ();
            if (dt != null) {
                modified = dt.to_unix ();
            }
            return "%lld:%lld:%u".printf (info.get_size (), modified, info.get_attribute_uint32 ("time::modified-usec"));
        } catch (Error error) {
        }
        return "missing";
    }

    private string escape_json (string value) {
        var builder = new StringBuilder ();
        for (int i = 0; i < value.length; i++) {
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
            i += c.to_string ().length - 1;
        }
        return builder.str;
    }

    private string[] extract_string_array_from_json (string json, string key) {
        string[] out = {};
        try {
            Regex section = new Regex ("\"" + key + "\"\\s*:\\s*\\[(.*?)\\]", RegexCompileFlags.DOTALL);
            MatchInfo info;
            if (!section.match (json, 0, out info)) {
                return out;
            }
            string inside = info.fetch (1);
            Regex token = new Regex ("\"((?:\\\\.|[^\"\\\\])*)\"");
            MatchInfo m;
            if (token.match (inside, 0, out m)) {
                do {
                    out += m.fetch (1).replace ("\\\"", "\"").replace ("\\\\", "\\");
                } while (m.next ());
            }
        } catch (Error error) {
        }
        return out;
    }

    private void write_audit_entry (string uri, string source, string decision, string reason, string risk, string graph) {
        string ts = OBrowserUtils.format_timestamp (OBrowserUtils.now_unix ());
        string line = "%s\tdecision=%s\trisk=%s\turi=%s\tsource=%s\treason=%s\tgraph=%s\n".printf (
            ts,
            decision,
            risk,
            uri.replace ("\t", " "),
            source.replace ("\t", " "),
            reason.replace ("\t", " "),
            graph.replace ("\t", " ")
        );
        try {
            var file = File.new_for_path (audit_log_path);
            var stream = file.append_to (FileCreateFlags.NONE);
            stream.write_all (line.data, null);
            stream.close ();
        } catch (Error error) {
            try {
                FileUtils.set_contents (audit_log_path, line);
            } catch (Error ignored) {
            }
        }
    }

    private bool fallback_should_block (string uri, string source_uri, out string reason) {
        reason = "";
        string clean = uri.strip ().down ();
        string source = source_uri.strip ().down ();
        if (clean == "") {
            return false;
        }
        if (clean.has_prefix ("javascript:")) {
            reason = "javascript scheme blocked (fallback)";
            return true;
        }
        if (clean.has_prefix ("data:text/html")) {
            reason = "data html blocked (fallback)";
            return true;
        }
        if (source.has_prefix ("https://") && clean.has_prefix ("http://")) {
            if (clean.contains (".js") || clean.contains (".mjs") || clean.contains (".css") || clean.contains (".wasm") || clean.contains ("/api/")) {
                reason = "mixed active content blocked (fallback)";
                return true;
            }
        }
        if (clean.has_prefix ("http://")) {
            if (clean.has_suffix (".exe") || clean.has_suffix (".msi") || clean.has_suffix (".dmg") || clean.has_suffix (".apk") || clean.has_suffix (".sh")) {
                reason = "insecure executable download blocked (fallback)";
                return true;
            }
        }
        return false;
    }
}
