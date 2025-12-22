/*  using GLib;

public class SuffixTreeNode : Object {
    public HashTable<string, SuffixTreeNode> children = new HashTable<string, SuffixTreeNode>(g_str_hash, g_str_equal);
    public Array<int> indexes = new Array<int>();
}

public class SuffixTree : Object {
    private SuffixTreeNode root = new SuffixTreeNode();
    private string text;

    public SuffixTree(string[] strings) {
        // Concatenate strings with separator
        text = strings.join("\u001F");
        insert_all_suffixes();
        compress(root);
    }

    // 1. Insert all suffixes naively
    private void insert_all_suffixes() {
        int n = text.length;
        for (int i = 0; i < n; i++) {
            var node = root;
            string suffix = text.substring(i);

            // Insert each suffix as a chain of single-char edges
            for (int j = 0; j < suffix.length; j++) {
                string key = suffix[j].to_string();
                if (!node.children.contains(key)) {
                    node.children[key] = new SuffixTreeNode();
                }
                node = node.children[key];
            }

            node.indexes.add(i);
        }
    }

    // 2. Compress paths with single child edges
    private void compress(SuffixTreeNode node) {
        foreach (var key in node.children.keys) {
            var child = node.children[key];
            compress(child);

            // Compress if child has only one edge
            while (child.children.size == 1 && child.indexes.size == 0) {
                var iter = child.children.get_iter();
                iter.next();
                string child_key = iter.key as string;
                var grandchild = iter.value as SuffixTreeNode;

                // Merge edge labels
                string new_key = key + child_key;
                node.children.remove(key);
                node.children[new_key] = grandchild;

                key = new_key;
                child = grandchild;
            }
        }
    }

    // Find all starting positions of a substring
    public Array<int> find_all(string pattern) {
        var node = root;
        int pos = 0;

        while (pos < pattern.length) {
            bool matched = false;
            foreach (var key in node.children.keys) {
                string edge = key;
                int l = 0;
                while (l < edge.length && pos + l < pattern.length && edge[l] == pattern[pos + l])
                    l++;

                if (l > 0) {
                    if (l == pattern.length - pos) {
                        node = node.children[edge];
                        return collect_indexes(node);
                    }
                    node = node.children[edge];
                    pos += l;
                    matched = true;
                    break;
                }
            }

            if (!matched) return new Array<int>();
        }

        return collect_indexes(node);
    }

    private Array<int> collect_indexes(SuffixTreeNode node) {
        var result = new Array<int>();
        foreach (var idx in node.indexes)
            result.add(idx);
        foreach (var child in node.children.values)
            foreach (var idx in collect_indexes(child))
                result.add(idx);
        return result;
    }
}  */