import Foundation

public enum UpdateRelaunch {
    /// Shell one-liner for the detached relauncher spawned right before the
    /// updated app terminates itself. It polls the old instance until it has
    /// fully exited before `open`-ing the replacement — a fixed sleep races a
    /// slow teardown, and `open` fired at a still-dying process silently
    /// no-ops (and `LSMultipleInstancesProhibited` would reject a launch while
    /// the old PID lingers). The wait is bounded (150 × 0.2 s = 30 s) so a
    /// wedged process can't stall the relaunch forever.
    public static func shellScript(pid: Int32, appPath: String) -> String {
        "i=0; while /bin/kill -0 \(pid) 2>/dev/null && [ $i -lt 150 ]; "
            + "do i=$((i+1)); sleep 0.2; done; /usr/bin/open \"\(appPath)\""
    }
}
