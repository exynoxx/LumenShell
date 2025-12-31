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
                // Key length + key
                uint32 key_len = (uint32)entry.key.length;
                buffer.append(uint32_to_bytes(key_len));
                buffer.append((uint8[])entry.key.data);
                
                // Value length + value
                uint32 val_len = (uint32)entry.value.length;
                buffer.append(uint32_to_bytes(val_len));
                buffer.append((uint8[])entry.value.data);
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
            uint32 magic = bytes_to_uint32(data[pos:pos+4]);
            pos += 4;
            
            if (magic != 0x48534D50) {
                stderr.printf("Invalid magic number\n");
                return null;
            }
            
            // Read version
            uint16 version = bytes_to_uint16(data[pos:pos+2]);
            pos += 2;
            
            if (version != 1) {
                stderr.printf("Unsupported version: %u\n", version);
                return null;
            }
            
            // Read count
            uint32 count = bytes_to_uint32(data[pos:pos+4]);
            pos += 4;
            
            var map = new HashMap<string, string>();
            
            // Read each key-value pair
            for (uint32 i = 0; i < count; i++) {
                // Read key
                if (pos + 4 > data.length) break;
                uint32 key_len = bytes_to_uint32(data[pos:pos+4]);
                pos += 4;
                
                if (pos + key_len > data.length) break;
                string key = (string)data[pos:pos+key_len];
                pos += key_len;
                
                // Read value
                if (pos + 4 > data.length) break;
                uint32 val_len = bytes_to_uint32(data[pos:pos+4]);
                pos += 4;
                
                if (pos + val_len > data.length) break;
                string val = (string)data[pos:pos+val_len];
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