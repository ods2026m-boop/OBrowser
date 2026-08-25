using GLib;

public class PasswordEntry : Object {
    public string origin { get; set; }
    public string username { get; set; }
    public string password { get; set; }
    public int64 updated_at { get; set; }

    public PasswordEntry (string origin, string username, string password, int64 updated_at) {
        this.origin = origin;
        this.username = username;
        this.password = password;
        this.updated_at = updated_at;
    }
}

public class PasswordManager : Object {
    private string vault_path;
    private string key_path;
    private string? cache_tsv;
    private bool use_keyring;

    public PasswordManager (AppPaths paths) {
        vault_path = Path.build_filename (paths.data_dir, "passwords.vault");
        key_path = Path.build_filename (paths.config_dir, "vault.key");
        use_keyring = OBrowserSecret.backend_available ();
        if (use_keyring) {
            cache_tsv = OBrowserSecret.load ("passwords", "vault");
        }
        migrate_legacy_vault ();
    }

    public PasswordEntry[] list_all () {
        string payload = cache_tsv ?? "";
        if (payload.strip () == "") {
            return {};
        }

        PasswordEntry[] entries = {};
        foreach (string line in payload.split ("\n")) {
            if (line.strip () == "") {
                continue;
            }
            string[] parts = line.split ("\t");
            if (parts.length < 4) {
                continue;
            }
            int64 updated = int64.parse (parts[3]);
            entries += new PasswordEntry (parts[0], parts[1], parts[2], updated);
        }
        return entries;
    }

    public void save_for_origin (string origin, string username, string password) {
        if (origin.strip () == "" || username.strip () == "" || password.strip () == "") {
            return;
        }
        PasswordEntry[] entries = list_all ();
        bool updated = false;
        for (int i = 0; i < entries.length; i++) {
            if (entries[i].origin == origin && entries[i].username == username) {
                entries[i].password = password;
                entries[i].updated_at = OBrowserUtils.now_unix ();
                updated = true;
                break;
            }
        }
        if (!updated) {
            entries += new PasswordEntry (origin, username, password, OBrowserUtils.now_unix ());
        }
        write_entries (entries);
    }

    public PasswordEntry? find_for_origin (string origin) {
        if (origin.strip () == "") {
            return null;
        }
        foreach (PasswordEntry entry in list_all ()) {
            if (entry.origin == origin) {
                return entry;
            }
        }
        return null;
    }

    public void remove_for_origin (string origin) {
        PasswordEntry[] filtered = {};
        foreach (PasswordEntry entry in list_all ()) {
            if (entry.origin != origin) {
                filtered += entry;
            }
        }
        write_entries (filtered);
    }

    private void write_entries (PasswordEntry[] entries) {
        StringBuilder plain = new StringBuilder ();
        foreach (PasswordEntry entry in entries) {
            plain.append ("%s\t%s\t%s\t%lld\n".printf (entry.origin, entry.username, entry.password, entry.updated_at));
        }
        cache_tsv = plain.str;
        if (use_keyring) {
            OBrowserSecret.store ("passwords", "vault", cache_tsv, "OBrowser saved passwords");
        }
    }

    private void migrate_legacy_vault () {
        if (!FileUtils.test (vault_path, FileTest.EXISTS)) {
            return;
        }
        if (!use_keyring) {
            warning ("Keyring unavailable: cannot migrate legacy password vault at %s. Leaving it in place.", vault_path);
            return;
        }
        string payload = "";
        try {
            FileUtils.get_contents (vault_path, out payload);
        } catch (Error error) {
            return;
        }
        if (payload.strip () == "") {
            try { FileUtils.remove (vault_path); } catch (Error e) { }
            try { FileUtils.remove (key_path); } catch (Error e) { }
            return;
        }

        uint8[] key = legacy_key_bytes ();
        if (key.length == 0) {
            warning ("Legacy vault key unavailable at %s: cannot decrypt vault at %s. Leaving it in place.", key_path, vault_path);
            return;
        }

        uint8[] decoded = Base64.decode (payload);
        for (int i = 0; i < decoded.length; i++) {
            decoded[i] = (uint8) (decoded[i] ^ key[i % key.length]);
        }
        var tsv_builder = new StringBuilder ();
        for (int i = 0; i < decoded.length; i++) {
            tsv_builder.append_c ((char) decoded[i]);
        }
        string tsv = tsv_builder.str;

        PasswordEntry[] entries = {};
        foreach (string line in tsv.split ("\n")) {
            if (line.strip () == "") {
                continue;
            }
            string[] parts = line.split ("\t");
            if (parts.length < 4) {
                continue;
            }
            entries += new PasswordEntry (parts[0], parts[1], parts[2], int64.parse (parts[3]));
        }
        write_entries (entries);

        bool persisted = entries.length == 0;
        if (!persisted) {
            string? verified = OBrowserSecret.load ("passwords", "vault");
            persisted = verified != null && verified.strip () != "";
        }
        if (persisted) {
            try { FileUtils.remove (vault_path); } catch (Error e) { }
            try { FileUtils.remove (key_path); } catch (Error e) { }
        } else {
            warning ("Keyring did not persist migrated passwords: leaving legacy vault at %s intact.", vault_path);
        }
    }

    private uint8[] legacy_key_bytes () {
        try {
            string key;
            FileUtils.get_contents (key_path, out key);
            if (key.data.length == 0) {
                return {};
            }
            return key.data;
        } catch (Error error) {
            return {};
        }
    }
}
