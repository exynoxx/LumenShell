namespace Utils {
    public class AliasArray<T> {
        private unowned T[] data;
        private int[] index;
        private int length;

        public AliasArray(T[] source, int? length = null) {
            this.data = source;
            this.length = (length == null) ? source.length : length;
            this.index = new int[this.length];
        }
        
        public T get(int i) {
            assert(i < this.length);
            return data[index[i]];
        }
        
        public void set(int i, T value) {
            assert(i < this.length);
            data[index[i]] = value;
        }
        
        public void alias_index(int i, int origin_i) {
            assert(i < this.length);
            index[i] = origin_i;
        }
    }
}