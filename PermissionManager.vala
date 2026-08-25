using Gtk;
using WebKit;

public class PermissionManager : Object {
    private Gtk.Window parent;

    public PermissionManager (Gtk.Window parent) {
        this.parent = parent;
    }

    public bool handle (PermissionRequest request, string origin) {
        string label = OBrowserUtils.permission_label (request);
        var dialog = new MessageDialog (parent, DialogFlags.MODAL, MessageType.QUESTION, ButtonsType.NONE,
            "%s request from %s".printf (label, origin.strip () != "" ? origin : "this page"));
        dialog.secondary_text = "Allow this request for the current session?";
        dialog.add_button ("_Deny", ResponseType.CANCEL);
        dialog.add_button ("_Allow", ResponseType.ACCEPT);

        bool allowed = dialog.run () == (int) ResponseType.ACCEPT;
        dialog.destroy ();

        if (allowed) {
            request.allow ();
        } else {
            request.deny ();
        }
        return true;
    }
}
