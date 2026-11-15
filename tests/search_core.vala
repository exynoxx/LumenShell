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
    return 0;
}
