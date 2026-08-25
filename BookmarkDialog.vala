using Gtk;

public class BookmarkDialog : Dialog {
    public signal void open_requested (string uri, bool new_tab);

    private BookmarkManager manager;
    private ListBox list;
    private Entry search_entry;

    public BookmarkDialog (Gtk.Window parent, BookmarkManager manager) {
        Object (title: "Bookmarks", transient_for: parent, modal: true);
        this.manager = manager;
        add_button ("_Close", ResponseType.CLOSE);
        default_width = 620;
        default_height = 420;

        Gtk.Widget content = get_content_area ();
        ((Box) content).spacing = 8;
        ((Box) content).margin = 12;

        search_entry = new Entry ();
        search_entry.placeholder_text = "Search bookmarks";
        search_entry.changed.connect (() => { refresh (); });
        ((Box) content).pack_start (search_entry, false, false, 0);

        list = new ListBox ();
        list.selection_mode = SelectionMode.NONE;
        var scroll = new ScrolledWindow (null, null);
        scroll.hexpand = true;
        scroll.vexpand = true;
        scroll.add (list);
        ((Box) content).pack_start (scroll, true, true, 0);

        refresh ();
        show_all ();
    }

    private void refresh () {
        foreach (Widget child in list.get_children ()) {
            list.remove (child);
        }

        BookmarkEntry[] entries = manager.search (search_entry.text);
        if (entries.length == 0) {
            var row = new ListBoxRow ();
            row.add (new Label ("No bookmarks found"));
            list.add (row);
            list.show_all ();
            return;
        }

        foreach (BookmarkEntry entry in entries) {
            list.add (build_row (entry));
        }
        list.show_all ();
    }

    private Widget build_row (BookmarkEntry entry) {
        var row = new ListBoxRow ();
        var outer = new Box (Orientation.VERTICAL, 6);
        outer.margin = 8;

        var title = new Label (entry.title);
        title.halign = Align.START;
        title.xalign = 0.0f;
        title.wrap = true;
        var uri = new Label (entry.uri);
        uri.halign = Align.START;
        uri.xalign = 0.0f;
        uri.selectable = true;

        var buttons = new Box (Orientation.HORIZONTAL, 6);
        var open_button = new Button.with_label ("Open");
        var new_tab_button = new Button.with_label ("Open in New Tab");
        var edit_button = new Button.with_label ("Edit");
        var delete_button = new Button.with_label ("Delete");
        open_button.clicked.connect (() => { open_requested (entry.uri, false); response (ResponseType.CLOSE); });
        new_tab_button.clicked.connect (() => { open_requested (entry.uri, true); response (ResponseType.CLOSE); });
        edit_button.clicked.connect (() => { edit_entry (entry); });
        delete_button.clicked.connect (() => { manager.remove (entry.uri); refresh (); });

        buttons.pack_start (open_button, false, false, 0);
        buttons.pack_start (new_tab_button, false, false, 0);
        buttons.pack_start (edit_button, false, false, 0);
        buttons.pack_start (delete_button, false, false, 0);

        outer.pack_start (title, false, false, 0);
        outer.pack_start (uri, false, false, 0);
        outer.pack_start (buttons, false, false, 0);
        row.add (outer);
        row.activate.connect (() => { open_requested (entry.uri, false); response (ResponseType.CLOSE); });
        return row;
    }

    private void edit_entry (BookmarkEntry entry) {
        var dialog = new Dialog.with_buttons ("Edit Bookmark", this, DialogFlags.MODAL,
            "_Cancel", ResponseType.CANCEL,
            "_Save", ResponseType.ACCEPT);
        Gtk.Widget box = dialog.get_content_area ();
        ((Box) box).spacing = 8;
        ((Box) box).margin = 12;
        var title_entry = new Entry ();
        title_entry.text = entry.title;
        var uri_entry = new Entry ();
        uri_entry.text = entry.uri;
        ((Box) box).pack_start (new Label ("Title"), false, false, 0);
        ((Box) box).pack_start (title_entry, false, false, 0);
        ((Box) box).pack_start (new Label ("URL"), false, false, 0);
        ((Box) box).pack_start (uri_entry, false, false, 0);
        dialog.show_all ();
        if (dialog.run () == (int) ResponseType.ACCEPT) {
            manager.update_entry (entry.uri, title_entry.text, uri_entry.text);
            refresh ();
        }
        dialog.destroy ();
    }
}
