using Gtk;
using WebKit;
using Gdk;

public class FindBar : Revealer {
    private Entry search_entry;
    private Label info_label;
    private Button next_button;
    private Button prev_button;
    private Button close_button;
    private CheckButton case_button;
    private BrowserTab? current_tab;

    public FindBar () {
        transition_type = RevealerTransitionType.SLIDE_DOWN;
        reveal_child = false;

        var frame = new Frame (null);
        add (frame);

        var box = new Box (Orientation.HORIZONTAL, 6);
        box.margin = 6;
        frame.add (box);

        search_entry = new Entry ();
        search_entry.hexpand = true;
        search_entry.placeholder_text = "Find in page";
        prev_button = new Button.with_label ("Prev");
        next_button = new Button.with_label ("Next");
        close_button = new Button.with_label ("Close");
        case_button = new CheckButton.with_label ("Case sensitive");
        info_label = new Label ("Type to search");
        info_label.halign = Align.START;

        box.pack_start (search_entry, true, true, 0);
        box.pack_start (prev_button, false, false, 0);
        box.pack_start (next_button, false, false, 0);
        box.pack_start (case_button, false, false, 0);
        box.pack_start (info_label, false, false, 0);
        box.pack_start (close_button, false, false, 0);

        search_entry.changed.connect (() => { search_now (); });
        search_entry.activate.connect (() => { find_next (); });
        search_entry.key_press_event.connect ((event) => {
            if ((event.state & ModifierType.SHIFT_MASK) != 0 && event.keyval == Key.Return) {
                find_previous ();
                return true;
            }
            return false;
        });
        case_button.toggled.connect (() => { search_now (); });
        next_button.clicked.connect (() => { find_next (); });
        prev_button.clicked.connect (() => { find_previous (); });
        close_button.clicked.connect (() => { hide_bar (); });
    }

    public void attach_tab (BrowserTab? tab) {
        current_tab = tab;
        if (current_tab != null) {
            current_tab.webview.get_find_controller ().found_text.connect ((matches) => {
                info_label.label = "%u matches".printf (matches);
            });
            current_tab.webview.get_find_controller ().failed_to_find_text.connect (() => {
                info_label.label = "No matches";
            });
        }
    }

    public void show_for_tab (BrowserTab? tab) {
        attach_tab (tab);
        reveal_child = true;
        search_entry.grab_focus ();
        search_entry.select_region (0, -1);
    }

    public void hide_bar () {
        reveal_child = false;
        if (current_tab != null) {
            current_tab.webview.get_find_controller ().search_finish ();
        }
    }

    private void search_now () {
        if (current_tab == null) {
            return;
        }

        string text = search_entry.text.strip ();
        if (text == "") {
            current_tab.webview.get_find_controller ().search_finish ();
            info_label.label = "Type to search";
            return;
        }

        FindOptions options = case_button.active ? FindOptions.NONE : FindOptions.CASE_INSENSITIVE;
        current_tab.webview.get_find_controller ().search (text, options, 500);
    }

    private void find_next () {
        if (current_tab != null && search_entry.text.strip () != "") {
            current_tab.webview.get_find_controller ().search_next ();
        }
    }

    private void find_previous () {
        if (current_tab != null && search_entry.text.strip () != "") {
            current_tab.webview.get_find_controller ().search_previous ();
        }
    }
}
