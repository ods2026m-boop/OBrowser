using Gtk;
using GLib;

public delegate void ShortcutAction ();

public class ShortcutManager : Object {
    private Gtk.ApplicationWindow owner;
    private Gtk.Application app;

    public ShortcutManager (Gtk.ApplicationWindow owner, Gtk.Application app) {
        this.owner = owner;
        this.app = app;
    }

    public void register (string action_name, string accel, owned ShortcutAction callback, string? secondary_accel = null) {
        var action = new SimpleAction (action_name, null);
        action.activate.connect (() => { callback (); });
        owner.add_action (action);
        if (secondary_accel != null && secondary_accel.strip () != "") {
            app.set_accels_for_action ("win." + action_name, { accel, secondary_accel });
        } else {
            app.set_accels_for_action ("win." + action_name, { accel });
        }
    }
}
