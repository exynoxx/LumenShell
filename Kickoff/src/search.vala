using GLib;

public class SuffixTreeNode {
    public HashTable<unichar, SuffixTreeNode> children;
    public string? label;
    public int start;
    public int end;
    public int string_index;
    
    public SuffixTreeNode(string? lbl = null, int s = -1, int e = -1, int idx = -1) {
        children = new HashTable<unichar, SuffixTreeNode>(direct_hash, direct_equal);
        label = lbl;
        start = s;
        end = e;
        string_index = idx;
    }
    
    public bool is_leaf() {
        return children.size() == 0;
    }
}

public class SuffixTree {
    private SuffixTreeNode root;
    private string[] strings;
    
    public SuffixTree(string[] input_strings) {
        root = new SuffixTreeNode();
        strings = input_strings;
        
        // Insert all suffixes
        for (int str_idx = 0; str_idx < strings.length; str_idx++) {
            insert_suffixes(strings[str_idx], str_idx);
        }
        
        // Compress the tree
        compress(root);
    }
    
    private void insert_suffixes(string str, int str_idx) {
        string text = str.ascii_down() + "$" + str_idx.to_string();
        
        for (int i = 0; i < text.length; i++) {
            insert_suffix(text, i, str_idx);
        }
    }
    
    private void insert_suffix(string text, int start, int str_idx) {
        SuffixTreeNode current = root;
        
        for (int i = start; i < text.length; i++) {
            unichar c = text[i];
            
            if (!current.children.contains(c)) {
                var new_node = new SuffixTreeNode(
                    text.substring(i, 1),
                    i,
                    i,
                    str_idx
                );
                current.children.set(c, new_node);
            }
            
            current = current.children.get(c);
        }
    }
    
    private void compress(SuffixTreeNode node) {
        // Post-order traversal to compress from leaves up
        var children_list = new List<SuffixTreeNode>();
        
        node.children.foreach((key, child) => {
            children_list.append(child);
        });
        
        foreach (var child in children_list) {
            compress(child);
        }
        
        // If node has exactly one child, merge with it
        if (node.children.size() == 1 && node != root) {
            SuffixTreeNode? only_child = null;
            node.children.foreach((key, child) => {
                only_child = child;
            });
            
            if (only_child != null) {
                // Merge labels
                if (node.label != null && only_child.label != null) {
                    node.label = node.label + only_child.label;
                    node.end = only_child.end;
                }
                
                // Adopt grandchildren
                node.children = only_child.children;
                node.string_index = only_child.string_index;
            }
        }
    }
    
    public List<string> find_all_containing(string pattern) {
        var results = new HashTable<int, bool>(direct_hash, direct_equal);
        
        // Find the node where pattern ends
        SuffixTreeNode? current = root;
        int pattern_idx = 0;
        
        while (pattern_idx < pattern.length && current != null) {
            unichar c = pattern[pattern_idx];
            
            if (!current.children.contains(c)) {
                return new List<string>();
            }
            
            current = current.children.get(c);
            
            if (current.label != null) {
                int label_idx = 0;
                while (label_idx < current.label.length && pattern_idx < pattern.length) {
                    if (current.label[label_idx] != pattern[pattern_idx]) {
                        return new List<string>();
                    }
                    label_idx++;
                    pattern_idx++;
                }
            } else {
                pattern_idx++;
            }
        }
        
        // Collect all string indices from this subtree
        if (current != null) {
            collect_string_indices(current, results);
        }
        
        // Convert indices to actual strings
        var result_list = new List<string>();
        results.foreach((idx, _) => {
            if (idx >= 0 && idx < strings.length) {
                result_list.append(strings[idx]);
            }
        });
        
        return (owned) result_list;
    }
    
    private void collect_string_indices(SuffixTreeNode node, HashTable<int, bool> indices) {
        if (node.is_leaf() && node.string_index >= 0) {
            indices.set(node.string_index, true);
        }
        
        node.children.foreach((key, child) => {
            collect_string_indices(child, indices);
        });
    }
    
    public void print_tree(SuffixTreeNode? node = null, string indent = "") {
        if (node == null) {
            node = root;
            stdout.printf("Root\n");
        }
        
        node.children.foreach((key, child) => {
            string label_str = child.label ?? ((string)key);
            stdout.printf("%s├─ %s", indent, label_str);
            
            if (child.is_leaf()) {
                stdout.printf(" [leaf, string:%d]\n", child.string_index);
            } else {
                stdout.printf("\n");
            }
            
            print_tree(child, indent + "│  ");
        });
    }
}

public static int main(string[] args) {
    stdout.printf("=== Suffix Tree Demo ===\n\n");
    
    var desktop_files = Utils.System.get_desktop_files();
    print("Apps %i\n", desktop_files.length);

    string[] test_strings = {};

    foreach (var desktop in desktop_files){
        var entries = Utils.Config.parse(desktop, "Desktop Entry");
        if (entries["Icon"] == null || entries["Exec"] == null || entries["Name"] == null) continue;

        var name = entries["Name"];
        test_strings += name;
    }
    
    stdout.printf("Building suffix tree for: ");
    foreach (var s in test_strings) {
        stdout.printf("\"%s\" ", s);
    }
    stdout.printf("\n\n");
    
    var tree = new SuffixTree(test_strings);
    
    stdout.printf("Tree structure:\n");
    tree.print_tree();
    
    stdout.printf("\n=== Search Tests ===\n");
    string[] patterns = {"ch", "brow", "internet"};
    
    foreach (var pattern in patterns) {
        stdout.printf("\nStrings containing \"%s\":\n", pattern);

        var a = get_monotonic_time();
        var results = tree.find_all_containing(pattern);
        var b = get_monotonic_time();
        stdout.printf("time: %lld\n", b-a);
        
        if (results.length() == 0) {
            stdout.printf("  (none)\n");
        } else {
            foreach (var str in results) {
                stdout.printf("  - %s\n", str);
            }
        }
    }

    var c = get_monotonic_time();
    var rr = new List<string>();
    foreach (var s in test_strings){
        if(s.contains("ch")){
            rr.append("ch");
        }
    }
    var d = get_monotonic_time();
    stdout.printf("time: %lld\n", d-c);
    
    return 0;
}