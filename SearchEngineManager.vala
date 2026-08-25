using GLib;

public class SearchEngineManager : Object {
    private SearchEngine[] engines;
    private int selected_index = 0;

    public SearchEngineManager () {
        engines = {
            new SearchEngine ("google", "Google", "https://www.google.com/search?q={query}")
        };
    }

    public SearchEngine[] list_engines () { return engines; }
    public SearchEngine current () { return engines[selected_index]; }
    public int current_index () { return selected_index; }

    public void set_selected_index (int index) {
        if (index >= 0 && index < engines.length) {
            selected_index = index;
        }
    }

    public SearchEngine? by_id (string id) {
        foreach (SearchEngine engine in engines) {
            if (engine.id == id) {
                return engine;
            }
        }
        return null;
    }

    public int index_of_id (string id) {
        for (int i = 0; i < engines.length; i++) {
            if (engines[i].id == id) {
                return i;
            }
        }
        return 0;
    }

    public string resolve_input (string raw_input) {
        string input = raw_input.strip ();
        if (input == "") {
            return "about:blank";
        }

        if (input.has_prefix ("obrowser://")) {
            return input;
        }

        if (input.has_prefix ("http://") || input.has_prefix ("https://") || input.has_prefix ("file://") || input.has_prefix ("about:")) {
            return input;
        }

        if (OBrowserUtils.is_probable_url (input)) {
            if (input.has_prefix ("localhost") || input.has_prefix ("127.") || input.has_prefix ("[::1]")) {
                return "http://" + input;
            }
            return "https://" + input;
        }

        return current ().build_search_url (input);
    }
}
