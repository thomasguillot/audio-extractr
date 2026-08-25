import Foundation

public struct ExtractionPlan: Sendable {
    public let sourceFile: URL
    public let trim: TrimRange
    public let speed: Double
    public let jobDir: URL

    public init(sourceFile: URL, trim: TrimRange, speed: Double, jobDir: URL) {
        self.sourceFile = sourceFile
        self.trim = trim
        self.speed = speed
        self.jobDir = jobDir
    }
}
