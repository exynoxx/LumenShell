// fzf FuzzyMatchV2-style matcher (DP + backtrace), GLib only.
namespace LumenSearch {
    public class Fuzzy {
        const int SCORE_MATCH = 16;
        const int GAP_START = -3;
        const int GAP_EXT = -1;
        const int BONUS_BOUNDARY = 8;
        const int BONUS_NONWORD = 8;
        const int BONUS_CAMEL123 = 7;
        const int BONUS_CONSECUTIVE = 4;
        const int FIRST_MULT = 2;
        const int MAX_DP_LEN = 1000;
        const int NEG = int.MIN / 2;

        // 0 nonword, 1 delimiter/space, 2 lower, 3 upper, 4 digit
        static int cls(unichar c) {
            if (c == '/' || c == '-' || c == '_' || c == '.' || c == ' ') return 1;
            if (c.isdigit()) return 4;
            if (c.isupper()) return 3;
            if (c.isalpha()) return 2;
            return 0;
        }

        static int bonus_for(int prev, int cur) {
            if (cur >= 2) {
                if (prev <= 1) return BONUS_BOUNDARY;
                if ((prev == 2 && cur == 3) || (prev != 4 && cur == 4)) return BONUS_CAMEL123;
            } else if (cur == 0) {
                return BONUS_NONWORD;
            }
            return 0;
        }

        public static bool match(string pattern, string text, out int score, out int[] positions) {
            score = 0;
            positions = {};
            if (pattern == "") return true;

            bool sens = false;
            unichar[] pc = {};
            for (int i = 0; i < pattern.length;) {
                unichar c = pattern.get_char(i);
                i += c.to_string().length;
                if (c.isupper()) sens = true;
                pc += c;
            }
            unichar[] tc = {};
            int[] off = {};
            int[] bon = {};
            int prev = 1;
            for (int i = 0; i < text.length;) {
                unichar c = text.get_char(i);
                off += i;
                i += c.to_string().length;
                tc += sens ? c : c.tolower();
                int k = cls(c);
                bon += bonus_for(prev, k);
                prev = k;
            }
            int m = pc.length, n = tc.length;
            if (m > n) return false;

            // greedy forward pass: feasibility + V1 fallback
            int[] g = new int[m];
            int pi = 0;
            for (int j = 0; j < n && pi < m; j++)
                if (tc[j] == pc[pi]) g[pi++] = j;
            if (pi < m) return false;

            if (n > MAX_DP_LEN) {
                // backward tighten from the last matched char
                pi = m - 1;
                for (int j = g[m - 1]; j >= 0 && pi >= 0; j--)
                    if (tc[j] == pc[pi]) g[pi--] = j;
                int sc = 0;
                for (int i = 0; i < m; i++) {
                    int j = g[i];
                    int b = bon[j];
                    if (i == 0) sc += SCORE_MATCH + b * FIRST_MULT;
                    else if (g[i - 1] == j - 1) sc += SCORE_MATCH + int.max(b, BONUS_CONSECUTIVE);
                    else sc += SCORE_MATCH + b + GAP_START + (j - g[i - 1] - 2) * GAP_EXT;
                }
                score = sc;
                positions = new int[m];
                for (int i = 0; i < m; i++) positions[i] = off[g[i]];
                return true;
            }

            // ponytail: full m*n tables, fine for names <=1000 chars and ~50k files; fzf's banded/pruned V2 if profiling demands.
            int[] M = new int[m * n];   // best score with pattern[i] matched exactly at j
            int[] G = new int[m * n];   // best score of M[i][k] followed by a gap through j
            for (int i = 0; i < m; i++) {
                for (int j = 0; j < n; j++) {
                    int idx = i * n + j;
                    int v = NEG;
                    if (tc[j] == pc[i]) {
                        if (i == 0) {
                            v = SCORE_MATCH + bon[j] * FIRST_MULT;
                        } else if (j > 0) {
                            int d = M[idx - n - 1];
                            if (d > NEG) v = d + SCORE_MATCH + int.max(bon[j], BONUS_CONSECUTIVE);
                            int gp = G[idx - n - 1];
                            if (gp > NEG) v = int.max(v, gp + SCORE_MATCH + bon[j]);
                        }
                    }
                    M[idx] = v;
                    int gv = NEG;
                    if (j > 0) {
                        if (M[idx - 1] > NEG) gv = M[idx - 1] + GAP_START;
                        if (G[idx - 1] > NEG) gv = int.max(gv, G[idx - 1] + GAP_EXT);
                    }
                    G[idx] = gv;
                }
            }
            int best = NEG, bj = -1;
            for (int j = 0; j < n; j++)
                if (M[(m - 1) * n + j] > best) { best = M[(m - 1) * n + j]; bj = j; }
            if (bj < 0) return false;

            score = best;
            int[] pos = new int[m];
            int j = bj;
            for (int i = m - 1; i >= 0; i--) {
                pos[i] = off[j];
                if (i == 0) break;
                int v = M[i * n + j];
                int d = M[(i - 1) * n + j - 1];
                if (j > 0 && d > NEG && d + SCORE_MATCH + int.max(bon[j], BONUS_CONSECUTIVE) == v) {
                    j--;
                    continue;
                }
                for (int k = j - 2; k >= 0; k--) {
                    int mk = M[(i - 1) * n + k];
                    if (mk > NEG && mk + GAP_START + (j - 1 - k - 1) * GAP_EXT + SCORE_MATCH + bon[j] == v) {
                        j = k;
                        break;
                    }
                }
            }
            positions = pos;
            return true;
        }
    }
}
