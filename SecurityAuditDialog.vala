using Gtk;

public class SecurityAuditDialog : Dialog {
    public SecurityAuditDialog (Gtk.Window parent, string[] lines) {
        Object (title: "Security Audit Log", transient_for: parent, modal: true);
        add_button ("_Close", ResponseType.CLOSE);
        default_width = 980;
        default_height = 520;

        var content = (Box) get_content_area ();
        content.spacing = 8;
        content.margin = 10;

        var info = new Label ("Recent security decisions from Nim policy engine");
        info.halign = Align.START;
        content.pack_start (info, false, false, 0);

        var view = new TextView ();
        view.editable = false;
        view.cursor_visible = false;
        view.monospace = true;
        var buffer = view.buffer;
        buffer.text = string.joinv ("\n", lines);

        var scroll = new ScrolledWindow (null, null);
        scroll.hexpand = true;
        scroll.vexpand = true;
        scroll.add (view);
        content.pack_start (scroll, true, true, 0);

        show_all ();
    }
}
