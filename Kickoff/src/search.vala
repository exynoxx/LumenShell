using GLib;

public class SearchDb {

    private string[] strings;
    private string[] last_search;

    public SearchDb(AppEntry[] apps) {
        foreach (var app in apps){
            strings += app.name;
        }
    }

    /*  public string[] query_all(string pattern){

    }

    public string[] query_cummulative(string pattern){

    }  */

}