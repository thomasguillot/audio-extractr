import Foundation

public enum UpdateRelaunch {
    /// Shell one-liner for the detached relauncher spawned just before the updated app
    /// terminates itself. It polls the old PID rather than sleeping a fixed interval:
    /// `open` fired at a still-dying process silently no-ops. Bounded at 150 × 0.2 s so a
    /// wedged process can't stall the relaunch forever.
    public static func shellScript(pid: Int32, appPath: String) -> String {
        "i=0; while /bin/kill -0 \(pid) 2>/dev/null && [ $i -lt 150 ]; "
            + "do i=$((i+1)); sleep 0.2; done; /usr/bin/open \"\(appPath)\""
    }
}
