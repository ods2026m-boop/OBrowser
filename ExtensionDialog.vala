using Gtk;

public class ExtensionDialog : Dialog {
    public signal void changed ();

    private ExtensionManager manager;
    private ListBox list;

    public ExtensionDialog (Gtk.Window parent, ExtensionManager manager) {
        Object (title: "Extensions", transient_for: parent, modal: true);
        this.manager = manager;
        add_button ("Install", 1001);
        add_button ("_Close", ResponseType.CLOSE);
        default_width = 700;
        default_height = 420;

        Gtk.Widget content = get_content_area ();
        var box = (Box) content;
        box.spacing = 8;
        box.margin = 12;

        var info = new Label ("Extensions are userscript/userstyle packs. New tabs pick up changes.");
        info.halign = Align.START;
        box.pack_start (info, false, false, 0);

        list = new ListBox ();
        list.selection_mode = SelectionMode.NONE;
        var scroll = new ScrolledWindow (null, null);
        scroll.hexpand = true;
        scroll.vexpand = true;
        scroll.add (list);
        box.pack_start (scroll, true, true, 0);

        response.connect ((id) => {
            if (id == 1001) {
                install_extension ();
            }
        });

        refresh ();
        show_all ();
    }

    private void refresh () {
        foreach (Widget child in list.get_children ()) {
            list.remove (child);
        }

        ExtensionEntry[] entries = manager.list_extensions ();
        if (entries.length == 0) {
            var row = new ListBoxRow ();
            row.add (new Label ("No extensions installed"));
            list.add (row);
            list.show_all ();
            return;
        }

        foreach (ExtensionEntry entry in entries) {
            list.add (build_row (entry));
        }
        list.show_all ();
    }

    public void refresh_for_external_change () {
        refresh ();
    }

    private Widget build_row (ExtensionEntry entry) {
        var row = new ListBoxRow ();
        var box = new Box (Orientation.HORIZONTAL, 8);
        box.margin = 8;

        var toggle = new CheckButton.with_label (entry.name);
        toggle.active = entry.enabled;
        toggle.toggled.connect (() => {
            manager.set_enabled (entry.id, toggle.active);
            changed ();
        });

        var subtitle = new Label ("script: %s | style: %s | version: %s | category: %s".printf (
            entry.script_file.strip () != "" ? entry.script_file : "none",
            entry.style_file.strip () != "" ? entry.style_file : "none",
            entry.version.strip () != "" ? entry.version : "n/a",
            entry.category.strip () != "" ? entry.category : "general"
        ));
        subtitle.halign = Align.START;

        var delete_button = new Button.with_label ("Remove");
        delete_button.clicked.connect (() => {
            manager.remove (entry.id);
            refresh ();
            changed ();
        });

        var left = new Box (Orientation.VERTICAL, 4);
        left.pack_start (toggle, false, false, 0);
        left.pack_start (subtitle, false, false, 0);

        box.pack_start (left, true, true, 0);
        box.pack_start (delete_button, false, false, 0);
        row.add (box);
        return row;
    }

    private void install_extension () {
        var dialog = new Dialog.with_buttons ("Install Extension", this, DialogFlags.MODAL, "_Cancel", ResponseType.CANCEL, "_Install", ResponseType.ACCEPT);
        var box = (Box) dialog.get_content_area ();
        box.spacing = 8;
        box.margin = 12;

        var name = new Entry ();
        name.placeholder_text = "Extension name";

        var script_chooser = new FileChooserButton ("Select userscript.js (optional)", FileChooserAction.OPEN);
        var style_chooser = new FileChooserButton ("Select userstyle.css (optional)", FileChooserAction.OPEN);

        box.pack_start (new Label ("Name"), false, false, 0);
        box.pack_start (name, false, false, 0);
        box.pack_start (script_chooser, false, false, 0);
        box.pack_start (style_chooser, false, false, 0);

        dialog.show_all ();
        if (dialog.run () == (int) ResponseType.ACCEPT) {
            string script = script_chooser.get_filename () ?? "";
            string style = style_chooser.get_filename () ?? "";
            if (manager.install_from_files (name.text, script, style)) {
                refresh ();
                changed ();
            }
        }
        dialog.destroy ();
    }
}
