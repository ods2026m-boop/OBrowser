using GLib;

namespace OBrowserSecret {
    private const string SCHEMA_NAME = "com.obrowser.app";
    private static Secret.Schema? schema = null;

    private static Secret.Schema get_schema () {
        if (schema == null) {
            schema = new Secret.Schema (SCHEMA_NAME, Secret.SchemaFlags.NONE,
                "obrowser-type", Secret.SchemaAttributeType.STRING,
                "obrowser-id", Secret.SchemaAttributeType.STRING);
        }
        return schema;
    }

    public static bool backend_available () {
        try {
            Secret.password_lookup_sync (get_schema (), null, "obrowser-type", "ping", "obrowser-id", "ping");
            return true;
        } catch (Error e) {
            return false;
        }
    }

    public static string? load (string type, string id) {
        try {
            return Secret.password_lookup_sync (get_schema (), null, "obrowser-type", type, "obrowser-id", id);
        } catch (Error e) {
            return null;
        }
    }

    public static void store (string type, string id, string secret, string label) {
        try {
            Secret.password_store_sync (get_schema (), null, label, secret, null, "obrowser-type", type, "obrowser-id", id);
        } catch (Error e) {
        }
    }

    public static void clear (string type, string id) {
        try {
            Secret.password_clear_sync (get_schema (), null, "obrowser-type", type, "obrowser-id", id);
        } catch (Error e) {
        }
    }
}
