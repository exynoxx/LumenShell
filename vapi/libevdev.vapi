// Hand-maintained: no upstream vapi ships. Only what lumen-settings uses.
[CCode (cheader_filename = "libevdev/libevdev.h")]
namespace Evdev {
    [CCode (cname = "EV_KEY")]
    public const uint EV_KEY;
    [CCode (cname = "libevdev_event_code_get_name")]
    public unowned string? event_code_get_name(uint type, uint code);
}
