using GLib;

public class SingleInstance {
    private const string FIFO_PATH = "/tmp/kickoff.fifo";

    public static bool existing_instance(){
        File fifo = File.new_for_path(FIFO_PATH);
        return fifo.query_exists(null);
    }

    public static void send_show(){
        // Open FIFO for writing
        int fd = FileStream.open(FIFO_PATH, "w");
        if (fd < 0) {
            stderr.printf("Cannot open FIFO for writing\n");
            return;
        }

        var fifo_stream = new IOChannel.unix_new(fd);
        fifo_stream.write("Hello from Vala\n");
        fifo_stream.flush();
        fifo_stream.close(null);
    }

    public static void setup(){
        int r = mkfifo(FIFO_PATH, 0666);
        if (r != 0) {
            stderr.printf("Failed to create FIFO\n");
            return 1;
        }

        // Open the FIFO for reading (non-blocking)
        int fd = FileStream.open(FIFO_PATH, "r");
        if (fd < 0) {
            stderr.printf("Failed to open FIFO\n");
            return;
        }

        var fifo_stream = new IOChannel.unix_new(fd);
        fifo_stream.set_encoding(null); // raw bytes
        fifo_stream.set_buffered(false);

        stdout.printf("Polling FIFO...\n");

        while (true) {
            // poll for readability
            PollFD[] fds = {
                PollFD(){fd=fd}
            };

            int ret = poll(fds, -1); // -1 = wait indefinitely

            if (ret > 0) {
                string? line = fifo_stream.read_line(null);
                if (line != null) {
                    stdout.printf("Received: %s\n", line);
                }
            }
        }
    }
}
