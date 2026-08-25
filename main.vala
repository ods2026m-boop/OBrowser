using Gtk;

public class OBrowserApp : Gtk.Application {
    public OBrowserApp () {
        Object (application_id: "com.obrowser.app", flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void activate () {
        BrowserWindow? window = active_window as BrowserWindow;
        if (window == null) {
            window = new BrowserWindow (this, false);
        }
        window.present ();
    }
}

public static int main (string[] args) {
    var app = new OBrowserApp ();
    return app.run (args);
}
