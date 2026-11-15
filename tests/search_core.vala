using LumenSearch;

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
    return 0;
}
