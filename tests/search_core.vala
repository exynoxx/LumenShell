using LumenSearch;

Item file_item(string name, string dir, string mime, bool boosted = false, bool junk = false) {
    var i = new Item();
    i.kind = ItemKind.FILE; i.name = name; i.dir = dir; i.mime = mime;
    i.uri = "file://" + dir + "/" + name; i.boosted = boosted; i.junk = junk;
    return i;
}

int main() {
    int s1, s2; int[] p;
    assert(Fuzzy.match("invpdf", "invoice-2025.pdf", out s1, out p));
    assert(p.length == 6 && p[0] == 0 && p[3] == 13);
    assert(!Fuzzy.match("xyz", "invoice-2025.pdf", out s1, out p));
    Fuzzy.match("inv", "invoice.pdf", out s1, out p);
    Fuzzy.match("inv", "main_overview.txt", out s2, out p);
    assert(s1 > s2);
    assert(!Fuzzy.match("Inv", "invoice.pdf", out s1, out p));
    assert(Fuzzy.match("inv", "Invoice.pdf", out s1, out p));
    assert(Fuzzy.match("ærpdf", "Ærø-faktura.pdf", out s1, out p));
    assert(p[0] == 0 && p[1] == 2);
    assert(Fuzzy.match("", "x", out s1, out p) && s1 == 0 && p.length == 0);
    assert(Types.lookup("PDF")[0] == "application/pdf");
    assert(Types.lookup("do") == null);                 // partial word is not a type
    var q = Query.parse("inv pdf");
    assert(q.terms.length == 1 && q.terms[0] == "inv" && q.hide_apps && !q.apps_only);
    assert(q.matches_mime("application/pdf") && !q.matches_mime("image/png"));
    var q2 = Query.parse("png jpg");
    assert(q2.terms.length == 0 && q2.matches_mime("image/jpeg") && q2.matches_mime("image/png"));
    assert(Query.parse("app fire").apps_only);
    var h = "/home/u";
    assert(Junk.is_junk("/home/u/.cache/foo/invoice.json", h));
    assert(Junk.is_junk("/home/u/.git/config", h));
    assert(Junk.is_junk("/home/u/go/pkg/mod/x.go", h));
    assert(Junk.is_junk("/home/u/src/app/node_modules/a/b.js", h));
    assert(!Junk.is_junk("/home/u/Documents/invoice-2025.pdf", h));
    var pdf  = file_item("invoice-2025.pdf", "/home/u/Documents", "application/pdf", true);
    var junk = file_item("invoice.json", "/home/u/.cache/foo", "application/json", false, true);
    var r = new Ranker(); r.set_items({ junk, pdf });
    var res = r.search(Query.parse("invoice"));
    assert(res.files[0].item == pdf || res.top.item == pdf);
    assert(res.top.item == pdf);
    var exact_junk = file_item("invpdf", "/home/u/.cache", "text/plain", false, true);
    r.set_items({ exact_junk, pdf });
    assert(r.search(Query.parse("invpdf")).top.item == pdf);
    r.set_items({ pdf, junk });
    var t = r.search(Query.parse("pdf"));
    assert(t.top.item == pdf && t.files.length == 0 && t.apps.length == 0);
    var tax = file_item("invoice.pdf", "/home/u/Documents/Tax", "application/pdf", true);
    r.set_items({ tax });
    var d = r.search(Query.parse("tax inv")).top;
    assert(d.dir_pos.length == 3 && d.name_pos.length == 3);
    r.set_items({ pdf, junk });
    r.search(Query.parse("inv"));
    assert(r.search(Query.parse("invo")).top.item == pdf);
    assert(r.search(Query.parse("invo")).files[0].item == junk);
    return 0;
}
