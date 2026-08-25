using Gtk;

public class DownloadDialog : Dialog {
    public signal void cancel_requested (string id);
    public signal void open_requested (string destination);
    public signal void open_folder_requested (string destination);
    public signal void clear_completed_requested ();

    private DownloadEntry[] entries;
    private ListBox list;

    public DownloadDialog (Gtk.Window parent, DownloadEntry[] entries) {
        Object (title: "Downloads", transient_for: parent, modal: true);
        this.entries = entries;
        add_button ("Clear Completed", 1001);
        add_button ("_Close", ResponseType.CLOSE);
        default_width = 720;
        default_height = 420;

        Gtk.Widget content = get_content_area ();
        ((Box) content).spacing = 8;
        ((Box) content).margin = 12;
        list = new ListBox ();
        list.selection_mode = SelectionMode.NONE;
        var scroll = new ScrolledWindow (null, null);
        scroll.hexpand = true;
        scroll.vexpand = true;
        scroll.add (list);
        ((Box) content).pack_start (scroll, true, true, 0);

        response.connect ((response_id) => {
            if (response_id == 1001) {
                clear_completed_requested ();
            }
        });

        refresh (entries);
        show_all ();
    }

    public void refresh (DownloadEntry[] entries) {
        this.entries = entries;
        foreach (Widget child in list.get_children ()) {
            list.remove (child);
        }

        if (entries.length == 0) {
            var row = new ListBoxRow ();
            row.add (new Label ("No downloads found"));
            list.add (row);
            list.show_all ();
            return;
        }

        foreach (DownloadEntry entry in entries) {
            list.add (build_row (entry));
        }
        list.show_all ();
    }

    private Widget build_row (DownloadEntry entry) {
        var row = new ListBoxRow ();
        var outer = new Box (Orientation.VERTICAL, 6);
        outer.margin = 8;

        string filename = entry.destination.strip () != "" ? Path.get_basename (entry.destination) : entry.uri;
        var title = new Label (filename);
        title.halign = Align.START;
        title.xalign = 0.0f;
        title.wrap = true;
        var progress = new ProgressBar ();
        progress.fraction = entry.progress;
        progress.text = "%d%%".printf ((int) (entry.progress * 100.0));
        progress.show_text = true;
        var subtitle = new Label ("%s\n%s\n%s".printf (entry.status, entry.destination, entry.uri));
        subtitle.halign = Align.START;
        subtitle.xalign = 0.0f;
        subtitle.selectable = true;

        var buttons = new Box (Orientation.HORIZONTAL, 6);
        var cancel_button = new Button.with_label ("Cancel");
        cancel_button.sensitive = entry.status == "running";
        cancel_button.clicked.connect (() => { cancel_requested (entry.id); });
        var open_button = new Button.with_label ("Open");
        open_button.sensitive = entry.destination.strip () != "";
        open_button.clicked.connect (() => { open_requested (entry.destination); });
        var folder_button = new Button.with_label ("Open Folder");
        folder_button.sensitive = entry.destination.strip () != "";
        folder_button.clicked.connect (() => { open_folder_requested (entry.destination); });
        buttons.pack_start (cancel_button, false, false, 0);
        buttons.pack_start (open_button, false, false, 0);
        buttons.pack_start (folder_button, false, false, 0);

        outer.pack_start (title, false, false, 0);
        outer.pack_start (progress, false, false, 0);
        outer.pack_start (subtitle, false, false, 0);
        outer.pack_start (buttons, false, false, 0);
        row.add (outer);
        return row;
    }
}
