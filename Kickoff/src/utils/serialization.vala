using Gee;
using GLib;

namespace Utils {

    class Serialization {
        
        public static uint8[] serialize(HashMap<string, string> map) {
            var buffer = new ByteArray();
            
            // Write magic number (4 bytes)
            uint32 magic = 0x48534D50; // "HSMP" in hex
            buffer.append(uint32_to_bytes(magic));
            
            // Write version (2 bytes)
            uint16 version = 1;
            buffer.append(uint16_to_bytes(version));
            
            // Write count (4 bytes)
            uint32 count = (uint32)map.size;
            buffer.append(uint32_to_bytes(count));
            
            // Write each key-value pair
            foreach (var entry in map.entries) {
                // Key length (excluding null terminator) + key bytes
                uint8[] key_bytes = entry.key.data;
                uint32 key_len = (uint32)(key_bytes.length); // Exclude null terminator
                buffer.append(uint32_to_bytes(key_len));
                
                // Append only the actual string data (without null terminator)
                for (uint32 i = 0; i < key_len; i++) {
                    buffer.append({key_bytes[i]});
                }
                
                // Value length + value bytes
                uint8[] val_bytes = entry.value.data;
                uint32 val_len = (uint32)(val_bytes.length); // Exclude null terminator
                buffer.append(uint32_to_bytes(val_len));
                
                for (uint32 i = 0; i < val_len; i++) {
                    buffer.append({val_bytes[i]});
                }
            }
            
            return buffer.data;
        }

        public static HashMap<string, string>? deserialize(uint8[] data) {
            if (data.length < 10) {
                stderr.printf("Data too small\n");
                return null;
            }
            
            uint32 pos = 0;
            
            // Read and verify magic number
            uint8[] magic_bytes = new uint8[4];
            for (int i = 0; i < 4; i++) {
                magic_bytes[i] = data[pos + i];
            }
            uint32 magic = bytes_to_uint32(magic_bytes);
            pos += 4;
            
            if (magic != 0x48534D50) {
                stderr.printf("Invalid magic number: 0x%08X\n", magic);
                return null;
            }
            
            // Read version
            uint8[] version_bytes = new uint8[2];
            for (int i = 0; i < 2; i++) {
                version_bytes[i] = data[pos + i];
            }
            uint16 version = bytes_to_uint16(version_bytes);
            pos += 2;
            
            if (version != 1) {
                stderr.printf("Unsupported version: %u\n", version);
                return null;
            }
            
            // Read count
            uint8[] count_bytes = new uint8[4];
            for (int i = 0; i < 4; i++) {
                count_bytes[i] = data[pos + i];
            }
            uint32 count = bytes_to_uint32(count_bytes);
            pos += 4;
            
            var map = new HashMap<string, string>();
            
            // Read each key-value pair
            for (uint32 i = 0; i < count; i++) {
                // Read key length
                if (pos + 4 > data.length) {
                    stderr.printf("Unexpected end of data reading key length\n");
                    return null;
                }
                
                uint8[] key_len_bytes = new uint8[4];
                for (int j = 0; j < 4; j++) {
                    key_len_bytes[j] = data[pos + j];
                }
                uint32 key_len = bytes_to_uint32(key_len_bytes);
                pos += 4;
                
                // Read key data
                if (pos + key_len > data.length) {
                    stderr.printf("Unexpected end of data reading key\n");
                    return null;
                }
                
                uint8[] key_bytes = new uint8[key_len + 1]; // +1 for null terminator
                for (uint32 j = 0; j < key_len; j++) {
                    key_bytes[j] = data[pos + j];
                }
                key_bytes[key_len] = 0; // Add null terminator
                string key = (string)key_bytes;
                pos += key_len;
                
                // Read value length
                if (pos + 4 > data.length) {
                    stderr.printf("Unexpected end of data reading value length\n");
                    return null;
                }
                
                uint8[] val_len_bytes = new uint8[4];
                for (int j = 0; j < 4; j++) {
                    val_len_bytes[j] = data[pos + j];
                }
                uint32 val_len = bytes_to_uint32(val_len_bytes);
                pos += 4;
                
                // Read value data
                if (pos + val_len > data.length) {
                    stderr.printf("Unexpected end of data reading value\n");
                    return null;
                }
                
                uint8[] val_bytes = new uint8[val_len + 1]; // +1 for null terminator
                for (uint32 j = 0; j < val_len; j++) {
                    val_bytes[j] = data[pos + j];
                }
                val_bytes[val_len] = 0; // Add null terminator
                string val = (string)val_bytes;
                pos += val_len;
                
                map.set(key, val);
            }

            return map;
        }
        
        public static void save_to_file(HashMap<string, string> map, string filepath) {
            try {
                var file = File.new_for_path(filepath);
                var parent = file.get_parent();
                if (parent != null && !parent.query_exists()) {
                    parent.make_directory_with_parents();
                }

                uint8[] data = serialize(map);
                FileUtils.set_data(filepath, data);

            } catch (Error e) {
                stderr.printf("Error saving: %s\n", e.message);
            }
        }
        
        public static HashMap<string, string>? load_from_file(string filepath) {
            try {

                if (!FileUtils.test(filepath, FileTest.EXISTS)) {
                    return null;
                }

                uint8[] data;
                FileUtils.get_data(filepath, out data);
                return deserialize(data);
                
            } catch (Error e) {
                stderr.printf("Error loading: %s\n", e.message);
                return null;
            }
        }
        
        // Helper methods for byte conversion (little-endian)
        private static uint8[] uint32_to_bytes(uint32 val) {
            uint8[] bytes = new uint8[4];
            bytes[0] = (uint8)(val & 0xFF);
            bytes[1] = (uint8)((val >> 8) & 0xFF);
            bytes[2] = (uint8)((val >> 16) & 0xFF);
            bytes[3] = (uint8)((val >> 24) & 0xFF);
            return bytes;
        }
        
        private static uint32 bytes_to_uint32(uint8[] bytes) {
            return ((uint32)bytes[0]) |
                ((uint32)bytes[1] << 8) |
                ((uint32)bytes[2] << 16) |
                ((uint32)bytes[3] << 24);
        }
        
        private static uint8[] uint16_to_bytes(uint16 val) {
            uint8[] bytes = new uint8[2];
            bytes[0] = (uint8)(val & 0xFF);
            bytes[1] = (uint8)((val >> 8) & 0xFF);
            return bytes;
        }
        
        private static uint16 bytes_to_uint16(uint8[] bytes) {
            return ((uint16)bytes[0]) | ((uint16)bytes[1] << 8);
        }
    }

}