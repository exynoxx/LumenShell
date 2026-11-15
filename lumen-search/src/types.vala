// Whole-word type names ("pdf", "doc", "png") mapped to MIME prefixes.
// Hardcoded on purpose: a partial word ("do") is never a type.
namespace LumenSearch {
    public class Types {
        public const string[] APP_WORDS = { "app", "application" };

        const string[] DOC = {
            "application/pdf",
            "application/vnd.oasis.opendocument.text",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml",
        };
        const string[] SHEET = {
            "application/vnd.oasis.opendocument.spreadsheet",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml",
            "text/csv",
        };
        const string[] SLIDES = {
            "application/vnd.oasis.opendocument.presentation",
            "application/vnd.ms-powerpoint",
            "application/vnd.openxmlformats-officedocument.presentationml",
        };
        const string[] ARCHIVE = {
            "application/zip",
            "application/x-tar",
            "application/x-7z",
            "application/gzip",
            "application/x-compressed-tar",
        };

        // Returns the MIME prefixes for an exact (case-insensitive) type word, or null.
        public static string[]? lookup(string word) {
            switch (word.down()) {
                case "pdf":                          return { "application/pdf" };
                case "doc": case "document":         return DOC;
                case "sheet": case "spreadsheet":    return SHEET;
                case "slides":                       return SLIDES;
                case "text":                         return { "text/" };
                case "image": case "photo": case "picture": return { "image/" };
                case "png":                          return { "image/png" };
                case "jpg": case "jpeg":             return { "image/jpeg" };
                case "svg":                          return { "image/svg" };
                case "music": case "audio": case "song": return { "audio/" };
                case "mp3":                          return { "audio/mpeg" };
                case "flac":                         return { "audio/flac" };
                case "video": case "movie":          return { "video/" };
                case "mp4":                          return { "video/mp4" };
                case "archive": case "zip":          return ARCHIVE;
                case "folder": case "dir":           return { "inode/directory" };
                default:                             return null;
            }
        }
    }
}
