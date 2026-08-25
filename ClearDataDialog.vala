using Gtk;
using WebKit;

public class ClearDataDialog : Dialog {
    private CheckButton history_button;
    private CheckButton downloads_button;
    private CheckButton session_button;
    private CheckButton website_button;

    public ClearDataDialog (Gtk.Window parent) {
        Object (title: "Clear Browsing Data", transient_for: parent, modal: true);
        add_button ("_Cancel", ResponseType.CANCEL);
        add_button ("_Clear", ResponseType.ACCEPT);

        Gtk.Widget content = get_content_area ();
        ((Box) content).spacing = 8;
        ((Box) content).margin = 12;

        history_button = new CheckButton.with_label ("Clear history");
        downloads_button = new CheckButton.with_label ("Clear downloads history");
        session_button = new CheckButton.with_label ("Clear saved session");
        website_button = new CheckButton.with_label ("Clear cookies, cache, and local storage");
        history_button.active = true;
        downloads_button.active = true;
        session_button.active = true;

        ((Box) content).pack_start (history_button, false, false, 0);
        ((Box) content).pack_start (downloads_button, false, false, 0);
        ((Box) content).pack_start (session_button, false, false, 0);
        ((Box) content).pack_start (website_button, false, false, 0);
        show_all ();
    }

    public bool clear_history () { return history_button.active; }
    public bool clear_downloads () { return downloads_button.active; }
    public bool clear_session () { return session_button.active; }
    public bool clear_website_data () { return website_button.active; }
}
