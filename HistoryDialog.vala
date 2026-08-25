using Gtk;

public class HistoryDialog : Dialog {
    public signal void open_requested (string uri, bool new_tab);
    public signal void clear_requested ();

    private HistoryManager manager;
    private ListBox list;
    private Entry search_entry;

    public HistoryDialog (Gtk.Window parent, HistoryManager manager) {
        Object (title: "History", transient_for: parent, modal: true);
        this.manager = manager;
        add_button ("Clear All", 1001);
        add_button ("_Close", ResponseType.CLOSE);
        default_width = 720;
        default_height = 460;

        Gtk.Widget content = get_content_area ();
        ((Box) content).spacing = 8;
        ((Box) content).margin = 12;

        search_entry = new Entry ();
        search_entry.placeholder_text = "Search history";
        search_entry.changed.connect (() => { refresh (); });
        ((Box) content).pack_start (search_entry, false, false, 0);

        list = new ListBox ();
        list.selection_mode = SelectionMode.NONE;
        var scroll = new ScrolledWindow (null, null);
        scroll.hexpand = true;
        scroll.vexpand = true;
        scroll.add (list);
        ((Box) content).pack_start (scroll, true, true, 0);

        response.connect ((response_id) => {
            if (response_id == 1001) {
                manager.clear ();
                clear_requested ();
                refresh ();
            }
        });

        refresh ();
        show_all ();
    }

    private void refresh () {
        foreach (Widget child in list.get_children ()) {
            list.remove (child);
        }

        HistoryEntry[] entries = manager.search (search_entry.text);
        if (entries.length == 0) {
            var row = new ListBoxRow ();
            row.add (new Label ("No history found"));
            list.add (row);
            list.show_all ();
            return;
        }

        foreach (HistoryEntry entry in entries) {
            list.add (build_row (entry));
        }
        list.show_all ();
    }

    private Widget build_row (HistoryEntry entry) {
        var row = new ListBoxRow ();
        var outer = new Box (Orientation.VERTICAL, 6);
        outer.margin = 8;
        var title = new Label (entry.title);
        title.halign = Align.START;
        title.xalign = 0.0f;
        title.wrap = true;
        var subtitle = new Label ("%s\n%s\nVisits: %d".printf (entry.uri, OBrowserUtils.format_timestamp (entry.visited_at), entry.visit_count));
        subtitle.halign = Align.START;
        subtitle.xalign = 0.0f;
        subtitle.selectable = true;

        var buttons = new Box (Orientation.HORIZONTAL, 6);
        var open_button = new Button.with_label ("Open");
        var new_tab_button = new Button.with_label ("New Tab");
        var delete_button = new Button.with_label ("Delete");
        open_button.clicked.connect (() => { open_requested (entry.uri, false); response (ResponseType.CLOSE); });
        new_tab_button.clicked.connect (() => { open_requested (entry.uri, true); response (ResponseType.CLOSE); });
        delete_button.clicked.connect (() => { manager.delete_entry (entry.uri); refresh (); });
        buttons.pack_start (open_button, false, false, 0);
        buttons.pack_start (new_tab_button, false, false, 0);
        buttons.pack_start (delete_button, false, false, 0);

        outer.pack_start (title, false, false, 0);
        outer.pack_start (subtitle, false, false, 0);
        outer.pack_start (buttons, false, false, 0);
        row.add (outer);
        row.activate.connect (() => { open_requested (entry.uri, false); response (ResponseType.CLOSE); });
        return row;
    }
}
