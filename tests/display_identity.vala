// MAINTENANCE_PLAN item 3/7: identical serial-less monitors must not share an ID.
int main() {
    var ids = new GenericArray<string>();
    var conns = new GenericArray<string>();
    foreach (var c in new string[] { "DP-1", "DP-2", "eDP-1" }) {
        ids.add(DisplayProfileStore.identity_for(c == "eDP-1" ? "BOE" : "Dell", "P2419H", "", "", c));
        conns.add(c);
    }
    DisplayProfileStore.disambiguate(ids, conns);
    assert(ids.get(0) == "edid:Dell:P2419H:@DP-1");
    assert(ids.get(1) == "edid:Dell:P2419H:@DP-2");
    assert(ids.get(2) == "edid:BOE:P2419H:");   // lone monitor keeps its saved ID
    return 0;
}
